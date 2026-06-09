#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// TableLab synthetic end-to-end smoke test.
//
// Exercises the REAL production paths a user hits — not just "does the site
// respond" (that's UptimeRobot's job). This catches the failure class that
// returns HTTP 200 while silently writing nothing (the 42501 GRANT bug, a
// broken logUsage insert, an RLS regression) — see CLAUDE.md.
//
// Layers, cheapest first:
//   1. Auth           — password sign-in against Supabase Auth
//   2. Sessions CRUD  — insert → read-back → delete via PostgREST (user JWT, RLS)
//   3. analyze-hand   — cache-hit call: function reachable + auth + cache read ($0)
//   4. analyze-hand   — forceRefresh call, then assert a FRESH ai_usage_log row
//                       appeared (the full AI write path). DEEP only — costs ~$0.034.
//
// Exit code 0 = all green. Non-zero = a step failed (fail the CI job → GitHub
// emails you; optionally also POSTs to SMOKE_ALERT_WEBHOOK).
//
// Env (all required unless noted):
//   SUPABASE_URL            e.g. https://xxxx.supabase.co
//   SUPABASE_ANON_KEY       public anon key
//   SMOKE_TEST_EMAIL        dedicated synthetic test account (see scripts/SMOKE_TEST.md)
//   SMOKE_TEST_PASSWORD     its password
//   SMOKE_DEEP              "1" to run the costed step 4 (daily). Omit/0 = skip.
//   SMOKE_ALERT_WEBHOOK     optional — Slack/Discord/Telegram-bridge incoming webhook
//
// Run locally:  node scripts/smoke-test.mjs
// ─────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = requireEnv("SUPABASE_URL").replace(/\/+$/, "");
const ANON_KEY = requireEnv("SUPABASE_ANON_KEY");
const EMAIL = requireEnv("SMOKE_TEST_EMAIL");
const PASSWORD = requireEnv("SMOKE_TEST_PASSWORD");
const DEEP = process.env.SMOKE_DEEP === "1";
const ALERT_WEBHOOK = process.env.SMOKE_ALERT_WEBHOOK || "";

// Fixed hand id so the cache-hit path (step 3) stays free across runs.
const SMOKE_HAND_ID = "00000000-0000-4000-8000-000000000001";

const REST = `${SUPABASE_URL}/rest/v1`;
const AUTH = `${SUPABASE_URL}/auth/v1`;
const FUNCTIONS = `${SUPABASE_URL}/functions/v1`;

function requireEnv(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`✗ Missing required env var: ${name}`);
    process.exit(2);
  }
  return v;
}

let failed = false;
const results = [];

async function step(name, fn) {
  const started = Date.now();
  try {
    await fn();
    const ms = Date.now() - started;
    console.log(`✓ ${name} (${ms}ms)`);
    results.push({ name, ok: true, ms });
  } catch (err) {
    const ms = Date.now() - started;
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`✗ ${name} (${ms}ms): ${msg}`);
    results.push({ name, ok: false, ms, error: msg });
    failed = true;
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

// ── Step 1: Auth ─────────────────────────────────────────────────────────────

let accessToken = "";
let userId = "";

async function signIn() {
  const res = await fetch(`${AUTH}/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  const body = await res.json().catch(() => ({}));
  assert(res.ok, `sign-in HTTP ${res.status}: ${JSON.stringify(body)}`);
  assert(body.access_token, "no access_token in sign-in response");
  assert(body.user?.id, "no user.id in sign-in response");
  accessToken = body.access_token;
  userId = body.user.id;
}

// Authenticated PostgREST headers (RLS context = this user)
function pgHeaders(extra = {}) {
  return {
    apikey: ANON_KEY,
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

// ── Step 2: Sessions CRUD roundtrip ──────────────────────────────────────────

async function sessionsRoundtrip() {
  const today = new Date().toISOString().slice(0, 10);
  const nowIso = new Date().toISOString();
  const row = {
    // The app always sets user_id explicitly on insert (supabase_service.dart);
    // the sessions RLS policy is WITH CHECK (user_id = auth.uid()), so omitting
    // it is a correct 42501 rejection — mirror the app and set it.
    user_id: userId,
    date: today,
    stakes: "1/2",
    game_type: "cash",
    buy_in: 100,
    cash_out: 100,
    profit_loss: 0,
    start_time: nowIso,
    end_time: nowIso,
    duration_minutes: 1,
    location: "SMOKE_TEST",
    notes: "automated-smoke-test — safe to delete",
    created_at: nowIso,
    currency: "CAD",
    country: "Canada",
  };

  // INSERT (return the created row so we get its id)
  const insRes = await fetch(`${REST}/sessions`, {
    method: "POST",
    headers: pgHeaders({ Prefer: "return=representation" }),
    body: JSON.stringify(row),
  });
  const insBody = await insRes.json().catch(() => ({}));
  assert(insRes.ok, `insert HTTP ${insRes.status}: ${JSON.stringify(insBody)}`);
  assert(Array.isArray(insBody) && insBody[0]?.id, "insert returned no row id");
  const id = insBody[0].id;

  try {
    // READ-BACK — proves the write actually landed (not a silent no-op 2xx)
    const selRes = await fetch(
      `${REST}/sessions?id=eq.${id}&select=id,location,profit_loss`,
      { headers: pgHeaders() },
    );
    const selBody = await selRes.json().catch(() => ([]));
    assert(selRes.ok, `read-back HTTP ${selRes.status}: ${JSON.stringify(selBody)}`);
    assert(
      Array.isArray(selBody) && selBody.length === 1 && selBody[0].id === id,
      `read-back did not return the inserted row (got ${JSON.stringify(selBody)})`,
    );
  } finally {
    // CLEANUP — always delete, even if read-back assertion threw
    const delRes = await fetch(`${REST}/sessions?id=eq.${id}`, {
      method: "DELETE",
      headers: pgHeaders(),
    });
    assert(delRes.ok, `cleanup delete HTTP ${delRes.status}`);
  }
}

// ── Minimal but schema-valid hand for analyze-hand ───────────────────────────

function smokeHand() {
  return {
    id: SMOKE_HAND_ID,
    tableSetup: {
      numSeats: 2,
      buttonSeat: 0,
      heroSeat: 0,
      smallBlind: 1,
      bigBlind: 2,
    },
    players: [
      { seat: 0, name: "Hero", stack: 200, isHero: true, holeCards: ["Ah", "Kh"] },
      { seat: 1, name: "Villain", stack: 200, isHero: false },
    ],
    streets: [
      {
        street: "preflop",
        communityCards: [],
        actions: [
          { seat: 0, type: "raise", amount: 6, openingBet: true },
          { seat: 1, type: "call", amount: 6 },
        ],
      },
      {
        street: "flop",
        communityCards: ["Qh", "7d", "2c"],
        actions: [
          { seat: 1, type: "check" },
          { seat: 0, type: "raise", amount: 8, openingBet: true },
          { seat: 1, type: "fold" },
        ],
      },
    ],
  };
}

async function callAnalyzeHand(forceRefresh) {
  const res = await fetch(`${FUNCTIONS}/analyze-hand`, {
    method: "POST",
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ hand: smokeHand(), reads: [], forceRefresh }),
  });
  const body = await res.json().catch(() => ({}));
  return { res, body };
}

// ── Step 3: analyze-hand reachable (cache hit — free) ────────────────────────

async function analyzeHandReachable() {
  const { res, body } = await callAnalyzeHand(false);
  assert(
    res.ok,
    `analyze-hand HTTP ${res.status}: ${JSON.stringify(body)}`,
  );
  // A real analysis (cached or fresh) always carries these fields.
  assert(
    typeof body.summary === "string" && typeof body.verdict === "string",
    `analyze-hand returned 200 but not a valid analysis: ${JSON.stringify(body).slice(0, 200)}`,
  );
}

// ── Step 4: full AI write path (DEEP only — costs one Claude call) ───────────

async function aiWritePath() {
  // Baseline: newest usage-log timestamp before we force a call.
  const before = await latestUsageLogAt();

  const { res, body } = await callAnalyzeHand(true);
  assert(res.ok, `forced analyze-hand HTTP ${res.status}: ${JSON.stringify(body)}`);
  assert(typeof body.summary === "string", "forced analyze-hand returned no analysis");

  // The smoking gun: a forced (uncached) call MUST append a new ai_usage_log
  // row. If the function 200s but no fresh row appears, the write path is
  // silently broken (the exact 42501 / logUsage failure mode).
  const after = await latestUsageLogAt();
  assert(after !== null, "no ai_usage_log row found after forced call — write path is silently broken");
  assert(
    before === null || after > before,
    `ai_usage_log did not advance (before=${before}, after=${after}) — logUsage write silently failed`,
  );
}

async function latestUsageLogAt() {
  const res = await fetch(
    `${REST}/ai_usage_log?user_id=eq.${userId}&function_name=eq.analyze-hand` +
      `&select=called_at&order=called_at.desc&limit=1`,
    { headers: pgHeaders() },
  );
  const body = await res.json().catch(() => ([]));
  assert(res.ok, `ai_usage_log read HTTP ${res.status}: ${JSON.stringify(body)}`);
  if (!Array.isArray(body) || body.length === 0) return null;
  return new Date(body[0].called_at).getTime();
}

// ── Alerting ─────────────────────────────────────────────────────────────────

async function alert(summary) {
  if (!ALERT_WEBHOOK) return;
  try {
    await fetch(ALERT_WEBHOOK, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: summary }),
    });
  } catch (e) {
    console.error("alert webhook failed:", e instanceof Error ? e.message : e);
  }
}

// ── Run ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`TableLab smoke test — ${new Date().toISOString()} (deep=${DEEP})`);

  await step("auth: password sign-in", signIn);

  // Everything below needs a token; bail early if auth failed.
  if (accessToken) {
    await step("sessions: insert → read-back → delete", sessionsRoundtrip);
    await step("analyze-hand: reachable (cache hit)", analyzeHandReachable);
    if (DEEP) {
      await step("analyze-hand: full AI write path (forced)", aiWritePath);
    }
  }

  console.log("");
  if (failed) {
    const broken = results.filter((r) => !r.ok).map((r) => `• ${r.name}: ${r.error}`);
    const summary = `🔴 TableLab smoke test FAILED (${new Date().toISOString()})\n${broken.join("\n")}`;
    console.error(summary);
    await alert(summary);
    process.exit(1);
  }
  console.log("🟢 All smoke checks passed.");
}

main().catch(async (e) => {
  const msg = e instanceof Error ? e.stack || e.message : String(e);
  console.error("Unhandled error in smoke test:", msg);
  await alert(`🔴 TableLab smoke test crashed: ${msg.slice(0, 300)}`);
  process.exit(1);
});
