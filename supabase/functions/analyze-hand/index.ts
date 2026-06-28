import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Anthropic from "npm:@anthropic-ai/sdk@0.36.3";
import { createClient } from "npm:@supabase/supabase-js@2";
import { reportError } from "../_shared/alert.ts";
import { CAPACITY_MESSAGE, isCapacityError } from "../_shared/capacity.ts";
import {
  buildPrompt,
  COACHING_TOOL,
  type PlayerRead,
  type PokerHand,
  readsSignature,
  SYSTEM_PROMPT,
} from "./prompt.ts";

const allowedOrigins = new Set([
  "https://tablelab.app",
  "https://www.tablelab.app",
]);

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowedOrigin = allowedOrigins.has(origin) ? origin : "https://tablelab.app";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

// Claude occasionally BOTCHES the tool call: it emits a per-street field as a
// STRING containing the literal `<parameter name="decision">…` tag instead of an
// object (and flattens the nested fields). That output is unparseable by the
// client (it crashes the analysis screen). It is non-deterministic at temp 0, so
// re-issuing the same call almost always yields clean output — detect it here so
// the caller can retry rather than cache + return garbage.
//
// ⚠️ This MUST stay aligned with the client's `_streetMalformed`
// (lib/models/ai_analysis_model.dart): any street shape the client flags as
// malformed must be flagged here too, or the server caches+bills a payload the
// client always rejects (a paid re-spend loop). Keep the two rule-sets in sync.
function isMalformedAnalysis(a: Record<string, unknown>): boolean {
  for (const s of ["preflop", "flop", "turn", "river"]) {
    const v = a[s];
    if (v == null) continue; // a street the hand never reached — fine
    // A present street MUST be a plain object — a string/number, or an ARRAY
    // (typeof array === "object" in JS, hence Array.isArray), is a botched call.
    if (typeof v !== "object" || Array.isArray(v)) return true;
    // …and a present `wasGto` must be a real bool (the client drops the street
    // otherwise — mirror that here so the two detectors agree).
    const g = (v as Record<string, unknown>).wasGto;
    if (g != null && typeof g !== "boolean") return true;
  }
  try {
    // The tool-parameter leak signature, wherever it lands.
    if (JSON.stringify(a).includes("<parameter")) return true;
  } catch (_) {
    return true; // unstringifiable (circular) → treat as malformed
  }
  return false;
}

// ── Rate limiting ─────────────────────────────────────────────────────────────

const EXEMPT_EMAILS = new Set(["rhtk.1234@gmail.com"]);
const HAND_DAILY_LIMIT = 20;

// deno-lint-ignore no-explicit-any
async function isRateLimited(supabase: any, userId: string, userEmail: string | undefined): Promise<boolean> {
  if (EXEMPT_EMAILS.has(userEmail ?? "")) return false;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from("ai_usage_log")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", "analyze-hand")
    .gte("called_at", since);
  if (error) {
    console.error("ai_usage_log rate-limit read failed:", error.code, error.message);
    // A silently failing count reads as 0 → unlimited AI calls. Alert.
    await reportError("analyze-hand", `rate-limit read failed: ${error.code} ${error.message}`);
  }
  return (count ?? 0) >= HAND_DAILY_LIMIT;
}

interface ClaudeUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

// deno-lint-ignore no-explicit-any
async function logUsage(supabase: any, userId: string, usage?: ClaudeUsage): Promise<void> {
  // One row per call (never overwritten) — the append-only spend ledger.
  const { error } = await supabase.from("ai_usage_log").insert({
    user_id: userId,
    function_name: "analyze-hand",
    input_tokens: usage?.input_tokens ?? 0,
    output_tokens: usage?.output_tokens ?? 0,
    cache_read_tokens: usage?.cache_read_input_tokens ?? 0,
    cache_write_tokens: usage?.cache_creation_input_tokens ?? 0,
  });
  if (error) {
    console.error("ai_usage_log insert failed:", error.code, error.message);
    // Broken spend ledger = no rate limiting + blind cost tracking. Alert.
    await reportError("analyze-hand", `ai_usage_log insert failed: ${error.code} ${error.message}`);
  }
}


// ── Entry point ───────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // All DB work uses the service role. The anon+JWT client above verifies the
    // user but its token was not propagating into PostgREST's RLS context, so
    // auth.uid() resolved to NULL — silently failing every insert (usage log +
    // analysis cache) and making the cache/rate-limit reads return nothing.
    // The user is already verified via getUser(); every query below is scoped
    // explicitly by user_id, so correctness no longer depends on RLS.
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const body = await req.json() as {
      hand: PokerHand;
      reads?: PlayerRead[];
      forceRefresh?: boolean;
      equityFacts?: unknown;
    };

    const { hand, reads = [], forceRefresh = false } = body;

    if (!hand?.id) {
      return new Response(JSON.stringify({ error: "Missing required field: hand" }), {
        status: 400,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // On-device equity facts are client-computed; sanitise before trusting them
    // in the prompt (cap count + length — this is the user's own analysis, but
    // keep the payload bounded regardless).
    const equityFacts: string[] = Array.isArray(body.equityFacts)
      ? body.equityFacts
        .filter((f): f is string => typeof f === "string")
        .slice(0, 8)
        .map((f) => f.slice(0, 600))
      : [];

    // Only pass reads for opponents actually in this hand
    const opponentNames = new Set(
      hand.players.filter((p) => !p.isHero).map((p) => p.name.toLowerCase()),
    );
    const relevantReads = reads.filter((r) =>
      opponentNames.has(r.playerLabel.toLowerCase())
    );
    const sig = readsSignature(relevantReads);

    // ── Cache check ──────────────────────────────────────────────────────────
    if (!forceRefresh) {
      const { data: cached, error: cacheErr } = await db
        .from("ai_hand_analyses")
        .select("analysis_json")
        .eq("user_id", user.id)
        .eq("hand_id", hand.id)
        .maybeSingle();
      if (cacheErr) {
        console.error("ai_hand_analyses cache read failed:", cacheErr.code, cacheErr.message);
        await reportError("analyze-hand", `cache read failed: ${cacheErr.code} ${cacheErr.message}`);
      }

      // Only a cache entry produced under the SAME reads is valid — otherwise
      // the cached coaching/equity would contradict the freshly-computed
      // on-device equity chips. A reads edit (or a pre-signature legacy row)
      // falls through to a fresh analysis. We do NOT re-validate the payload for
      // malformation here on purpose: a legacy malformed row is served as-is and
      // the hardened client flags it (`HandCoachingAnalysis.malformed`) and shows
      // a re-analyze prompt. Self-healing in this branch would fire a fresh PAID
      // Claude call on a passive screen-open (initState auto-runs the analysis),
      // silently spending a quota slot the user never asked for — let the
      // explicit Re-analyze (forceRefresh) tap heal it instead.
      if (cached && cached.analysis_json?._readsSignature === sig) {
        return new Response(JSON.stringify(cached.analysis_json), {
          headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    // ── Rate limit check ─────────────────────────────────────────────────────
    if (await isRateLimited(db, user.id, user.email ?? undefined)) {
      return new Response(
        JSON.stringify({ error: "Daily analysis limit reached. Please try again tomorrow." }),
        { status: 429, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
      );
    }

    // ── Call Claude ──────────────────────────────────────────────────────────
    const anthropic = new Anthropic({
      apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    });

    const built = buildPrompt(hand, relevantReads, equityFacts);

    // Retry once on a malformed tool call (see isMalformedAnalysis). Each
    // attempt keeps the original 50s single-call ceiling, within a 90s total
    // budget so one retry fits; if it never validates we return an error rather
    // than cache + serve garbage.
    const DEADLINE = Date.now() + 90000;
    const PER_ATTEMPT_MS = 50000;
    const MAX_ATTEMPTS = 2;
    let analysis: Record<string, unknown> | null = null;
    // deno-lint-ignore no-explicit-any
    let usage: any = null;
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const remaining = DEADLINE - Date.now();
      // A real analyze-hand call needs ~20-30s; don't start a doomed retry that
      // would only time out into the timeout path.
      if (remaining < 20000) break;

      const claudeCall = anthropic.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        temperature: 0,
        system: [
          { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
        ],
        tools: [COACHING_TOOL],
        tool_choice: { type: "tool", name: "provide_hand_coaching" },
        messages: [{ role: "user", content: built.prompt }],
      });
      let timer: ReturnType<typeof setTimeout> | undefined;
      const timeoutPromise = new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("CLAUDE_TIMEOUT")),
          Math.min(remaining, PER_ATTEMPT_MS),
        );
      });
      // clearTimeout on both paths so a won race doesn't leave a dangling timer
      // (which would keep the instance alive / fire an unhandled rejection).
      const message = await Promise.race([claudeCall, timeoutPromise])
        .finally(() => clearTimeout(timer));
      usage = message.usage; // the delivered attempt's usage (cache row + logUsage)

      const toolBlock = message.content.find((c) => c.type === "tool_use");
      if (!toolBlock || toolBlock.type !== "tool_use") {
        if (attempt < MAX_ATTEMPTS) continue;
        throw new Error("Model did not return coaching tool call");
      }
      // deno-lint-ignore no-explicit-any
      const candidate = (toolBlock as any).input as Record<string, unknown>;
      if (!isMalformedAnalysis(candidate)) {
        analysis = candidate;
        break;
      }
      console.warn(`analyze-hand: malformed tool output (attempt ${attempt}/${MAX_ATTEMPTS})`);
    }

    if (!analysis || !usage) {
      // Every attempt was malformed (or out of time): don't cache garbage — the
      // hardened client shows a "re-analyze" prompt on this error. We DO log the
      // last attempt's usage (counting ONE slot) as a rate-limit backstop: the
      // screen auto-runs in initState, so without it a hand that deterministically
      // malforms would re-burn paid Claude calls on every open with no ceiling.
      // (Failed retries are real spend; one log row per failed request bounds it
      // to the 20/day cap instead of unlimited — the inverse of the GRANTs footgun.)
      if (usage) await logUsage(db, user.id, usage);
      await reportError("analyze-hand", "tool output malformed after retries");
      return new Response(
        JSON.stringify({ error: "Analysis failed. Please try again." }),
        { status: 502, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
      );
    }

    // ── Log usage ────────────────────────────────────────────────────────────
    // ONCE, for the delivered analysis only — one row = one unit of the 20/day
    // quota (isRateLimited counts ai_usage_log rows). A discarded malformed
    // attempt is deliberately NOT logged: the model's botched call must not burn
    // the user's quota (a retried hand still counts as a single analysis).
    await logUsage(db, user.id, usage);

    // Attach the deterministic [FACT] lines so the client can show "what the
    // AI was told" verbatim — not model output, never trusted to the model.
    analysis.facts = built.facts;
    // Stamp the reads signature so the cache entry is only reused under the
    // same reads (see readsSignature). Client ignores underscore-prefixed keys.
    analysis._readsSignature = sig;

    // ── Cache result ─────────────────────────────────────────────────────────
    const { error: cacheWriteErr } = await db.from("ai_hand_analyses").upsert(
      {
        user_id: user.id,
        hand_id: hand.id,
        analysis_json: analysis,
        model_used: "claude-sonnet-4-6",
        tokens_used: usage.input_tokens + usage.output_tokens,
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cache_read_tokens: usage.cache_read_input_tokens ?? 0,
        cache_write_tokens: usage.cache_creation_input_tokens ?? 0,
        // Reset any thumbs rating: this writes a NEW analysis (re-analyze
        // overwrites the cache), so a rating left from the previous coaching must
        // not carry over onto different coaching (it would pollute the eval set).
        rating: null,
        rated_at: null,
      },
      { onConflict: "user_id,hand_id" },
    );
    if (cacheWriteErr) {
      console.error("ai_hand_analyses upsert failed:", cacheWriteErr.code, cacheWriteErr.message);
      // A failed cache write means the next identical request pays for a fresh
      // Claude call (the exact FK bug that bit the smoke test). Alert.
      await reportError("analyze-hand", `ai_hand_analyses upsert failed: ${cacheWriteErr.code} ${cacheWriteErr.message}`);
    }

    return new Response(JSON.stringify(analysis), {
      headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("analyze-hand error:", msg);
    // "At capacity" (spend cap / credit / rate-limit / overload): clear, honest
    // 503 and NO alert — every call fails at once when the cap binds, so per-call
    // alerts would flood the ops channel; spend is already monitored elsewhere.
    if (msg !== "CLAUDE_TIMEOUT" && isCapacityError(err)) {
      return new Response(
        JSON.stringify({ error: CAPACITY_MESSAGE }),
        { status: 503, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
      );
    }
    await reportError("analyze-hand", msg);
    if (msg === "CLAUDE_TIMEOUT") {
      return new Response(
        JSON.stringify({ error: "Analysis timed out. Please try again." }),
        { status: 504, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
      );
    }
    return new Response(
      JSON.stringify({ error: "Analysis failed. Please try again." }),
      { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
    );
  }
});
