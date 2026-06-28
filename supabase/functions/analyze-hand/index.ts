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
      // falls through to a fresh analysis.
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

    const claudeCall = anthropic.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 2000,
      temperature: 0,
      system: [
        {
          type: "text",
          text: SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" },
        },
      ],
      tools: [COACHING_TOOL],
      tool_choice: { type: "tool", name: "provide_hand_coaching" },
      messages: [{ role: "user", content: built.prompt }],
    });

    const timeoutPromise = new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("CLAUDE_TIMEOUT")), 50000),
    );

    const message = await Promise.race([claudeCall, timeoutPromise]);

    const toolBlock = message.content.find((c) => c.type === "tool_use");
    if (!toolBlock || toolBlock.type !== "tool_use") {
      throw new Error("Model did not return coaching tool call");
    }
    // deno-lint-ignore no-explicit-any
    const analysis = (toolBlock as any).input as Record<string, unknown>;
    // Attach the deterministic [FACT] lines so the client can show "what the
    // AI was told" verbatim — not model output, never trusted to the model.
    analysis.facts = built.facts;
    // Stamp the reads signature so the cache entry is only reused under the
    // same reads (see readsSignature). Client ignores underscore-prefixed keys.
    analysis._readsSignature = sig;

    // ── Log usage ────────────────────────────────────────────────────────────
    await logUsage(db, user.id, message.usage);

    // ── Cache result ─────────────────────────────────────────────────────────
    const { error: cacheWriteErr } = await db.from("ai_hand_analyses").upsert(
      {
        user_id: user.id,
        hand_id: hand.id,
        analysis_json: analysis,
        model_used: "claude-sonnet-4-6",
        tokens_used: message.usage.input_tokens + message.usage.output_tokens,
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens,
        cache_read_tokens: message.usage.cache_read_input_tokens ?? 0,
        cache_write_tokens: message.usage.cache_creation_input_tokens ?? 0,
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
