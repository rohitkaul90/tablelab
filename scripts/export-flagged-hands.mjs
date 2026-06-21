#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// TableLab eval harness — export user-rated hands as benchmark spots.
//
// Pulls the recorded hands the OPERATOR rated on their AI hand analysis
// (ai_hand_analyses.rating: -1 thumbs-down, +1 thumbs-up), de-identifies each,
// and writes them as eval-harness spots so Stage 1 (bake_fixtures.dart) can bake
// them alongside the Pluribus corpus and Stage 2 (score.ts) can score them on
// the SAME three dimensions (card-logic, verdict self-consistency, forced
// decision) — now with the user's satisfaction signal carried through so the
// report can cross-tab "disliked × objectively-clean" (the subjective gap).
//
// The rating is a SELECTION FILTER, not a label: the harness ground truth stays
// independent (Dart evaluator). Thumbs-down picks high-yield hands; thumbs-up is
// a "satisfied" control set. See memory eval-user-flagged-hands + EVAL_HARNESS.md.
//
// ⚠️ SCOPE: operator's own hands only. Needs the SERVICE-ROLE key (ai_hand_analyses
// + hands are RLS-scoped per user). Run LOCALLY, never in CI (mirrors
// scripts/ai-cost-report.mjs). De-identifies before anything touches disk:
// villain hole cards nulled (REQUIRED — the pipeline models villains by range,
// result-independent), player names + user_id/session_id stripped.
//
// Env:
//   SUPABASE_URL                https://xxxx.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY   service-role key (Supabase → Settings → API)
//   OPERATOR_USER_ID            (optional) the user whose hands to export
//   OPERATOR_EMAIL              (optional) resolve the id from this email instead
//                               (default: rhtk.1234@gmail.com — the exempt account)
//
// Flags:
//   --rating=both | -1 | 1   which ratings to pull (default: both)
//   --include-quick          include Quick Hand entries (synthesized villain
//                            line → weaker spot; excluded by default)
//
// Run:  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/export-flagged-hands.mjs
// Then: dart run tool/eval/bake_fixtures.dart tool/eval/spots-user.json
//       deno run --allow-read --allow-write --allow-env --allow-net tool/eval/score.ts
// ─────────────────────────────────────────────────────────────────────────────

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const SUPABASE_URL = requireEnv("SUPABASE_URL").replace(/\/+$/, "");
const SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const OPERATOR_EMAIL = process.env.OPERATOR_EMAIL ?? "rhtk.1234@gmail.com";

const SAMPLES_DIR = "tool/eval/samples/user";
const MANIFEST_PATH = "tool/eval/spots-user.json";

// Reproducible/diffable + de-identifying: every exported hand is stamped with
// the same fixed instant the Pluribus baker uses (no real timestamps on disk).
const EVAL_PLAYED_AT = "2026-01-01T00:00:00.000Z";

function requireEnv(name) {
  const v = process.env[name];
  if (!v) { console.error(`✗ Missing required env var: ${name}`); process.exit(2); }
  return v;
}

function authHeaders(extra = {}) {
  return { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, ...extra };
}

function parseRatings() {
  const arg = process.argv.find((a) => a.startsWith("--rating="));
  const val = arg ? arg.slice("--rating=".length) : "both";
  if (val === "both") return [-1, 1];
  if (val === "-1") return [-1];
  if (val === "1") return [1];
  console.error(`✗ --rating must be one of: both | -1 | 1 (got "${val}")`);
  process.exit(2);
}

// ── Resolve the operator's user id ────────────────────────────────────────────
async function resolveOperatorId() {
  if (process.env.OPERATOR_USER_ID) return process.env.OPERATOR_USER_ID;
  const target = OPERATOR_EMAIL.toLowerCase();
  for (let page = 1; ; page++) {
    const res = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=1000`,
      { headers: authHeaders() },
    );
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`admin/users HTTP ${res.status}: ${body.slice(0, 200)}`);
    }
    const body = await res.json();
    const users = Array.isArray(body) ? body : (body.users ?? []);
    const found = users.find((u) => (u.email ?? "").toLowerCase() === target);
    if (found) return found.id;
    if (users.length < 1000) break;
  }
  throw new Error(
    `operator email ${OPERATOR_EMAIL} not found — set OPERATOR_USER_ID explicitly`,
  );
}

// ── Fetch rated analyses joined to their hands (paginated like ai-cost-report) ─
async function fetchRated(operatorId, rating) {
  const select =
    "hand_id,rating,rated_at,hands!inner(id,hand_data,played_at,session_id)";
  const query =
    `select=${encodeURIComponent(select)}&rating=eq.${rating}` +
    `&user_id=eq.${operatorId}&order=rated_at.asc`;
  const pageSize = 1000;
  const rows = [];
  for (let from = 0; ; from += pageSize) {
    const to = from + pageSize - 1;
    const res = await fetch(`${SUPABASE_URL}/rest/v1/ai_hand_analyses?${query}`, {
      headers: authHeaders({ Range: `${from}-${to}`, "Range-Unit": "items" }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`ai_hand_analyses read HTTP ${res.status}: ${body.slice(0, 200)}`);
    }
    const page = await res.json();
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return rows;
}

// ── De-identify a hand_data JSONB into an eval-ready PokerHand JSON ────────────
// hand_data omits the row-level id/userId/playedAt (those are table columns the
// app re-attaches on read), so we add them back as eval constants.
function deidentify(handData, newId) {
  const d = structuredClone(handData);
  d.id = newId;
  d.userId = "eval";
  delete d.sessionId;
  d.playedAt = EVAL_PLAYED_AT;
  for (const p of d.players ?? []) {
    if (p.isHero) {
      p.name = "Hero";
    } else {
      p.name = `P${p.seat}`;
      // Result-independence: villains are modeled by RANGE; their real cards
      // must never reach a fixture (the prompt + equity check both omit them).
      delete p.holeCards;
    }
  }
  return d;
}

function reachesFlop(handData) {
  return (handData.streets ?? []).some(
    (s) => s.street !== "preflop" && (s.communityCards?.length ?? 0) >= 3,
  );
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  const ratings = parseRatings();
  const includeQuick = process.argv.includes("--include-quick");

  const operatorId = await resolveOperatorId();
  console.log(`Operator: ${operatorId}  (ratings: ${ratings.join(", ")}${includeQuick ? "; incl. quick" : ""})`);

  mkdirSync(SAMPLES_DIR, { recursive: true });

  // Idempotent merge: keep any existing spots, overwrite by id.
  const byId = new Map();
  if (existsSync(MANIFEST_PATH)) {
    for (const s of JSON.parse(readFileSync(MANIFEST_PATH, "utf8"))) byId.set(s.id, s);
  }

  let exported = 0, skippedQuick = 0, skippedNoFlop = 0;
  for (const rating of ratings) {
    const rows = await fetchRated(operatorId, rating);
    console.log(`  rating ${rating > 0 ? "+1" : rating}: ${rows.length} rated hand(s)`);
    for (const row of rows) {
      const hd = row.hands?.hand_data;
      if (!hd) continue;
      if (hd.isQuickEntry === true && !includeQuick) { skippedQuick++; continue; }
      if (!reachesFlop(hd)) { skippedNoFlop++; continue; }

      const id = `user-${String(row.hand_id).replace(/-/g, "").slice(0, 12)}`;
      const clean = deidentify(hd, id);
      writeFileSync(
        `${SAMPLES_DIR}/${id}.json`,
        JSON.stringify(clean, null, 2) + "\n",
      );
      byId.set(id, {
        id,
        file: `${SAMPLES_DIR}/${id}.json`,
        source: "user-flagged",
        hero: (clean.tableSetup?.heroSeat ?? 0) + 1,
        bucket: rating === -1 ? "user-down" : "user-up",
        reads: [],
        userRating: rating,
        ratedAt: row.rated_at,
      });
      exported++;
    }
  }

  const manifest = [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
  writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + "\n");

  console.log(
    `\nExported ${exported} hand(s) → ${SAMPLES_DIR}/  (manifest: ${MANIFEST_PATH}, ${manifest.length} total spots)` +
    `${skippedQuick ? `\nSkipped ${skippedQuick} quick-hand (use --include-quick to keep)` : ""}` +
    `${skippedNoFlop ? `\nSkipped ${skippedNoFlop} preflop-only (no board to score)` : ""}`,
  );
  console.log(`\nNext:\n  dart run tool/eval/bake_fixtures.dart ${MANIFEST_PATH}\n  deno run --allow-read --allow-write --allow-env --allow-net tool/eval/score.ts`);
}

main().catch((e) => { console.error(`✗ ${e instanceof Error ? e.message : e}`); process.exit(1); });
