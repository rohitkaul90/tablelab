#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// TableLab daily health digest — one green/red Discord message each morning
// tying together the smoke test (#1) and the AI cost monitor (#3).
//
// The failure alerts are alert-on-failure (silence = healthy); this is the
// positive heartbeat that catches "silently dead monitoring" (disabled cron,
// deleted webhook, expired secret). If the morning message stops arriving,
// that absence IS the alert. Runs from .github/workflows/daily-digest.yml.
//
// Env:
//   SUPABASE_URL                 https://xxxx.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY    service-role key (ai_usage_log is RLS-scoped
//                                per user; cross-user aggregation must bypass RLS)
//   ALERT_WEBHOOK                Discord webhook with /slack suffix ({"text"} body)
//   GITHUB_TOKEN                 provided by Actions (actions:read) for smoke runs
//   GITHUB_REPOSITORY            owner/repo (auto-set on Actions runners)
//   SMOKE_TEST_EMAIL             optional — excludes the synthetic account from
//                                activity counts (omit and counts include it)
//   AI_SPEND_CAP                 optional, default 100
//
// Flags:  --dry-run   print the message instead of posting it
//
// Privacy: aggregate numbers only — never put emails/user IDs in the message.
// ─────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = requireEnv("SUPABASE_URL").replace(/\/+$/, "");
const SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const DRY_RUN = process.argv.includes("--dry-run");
const WEBHOOK = DRY_RUN ? process.env.ALERT_WEBHOOK : requireEnv("ALERT_WEBHOOK");
const CAP = Number(process.env.AI_SPEND_CAP ?? "100");
const REPO = process.env.GITHUB_REPOSITORY ?? "";
const GH_TOKEN = process.env.GITHUB_TOKEN ?? "";
const SMOKE_EMAIL = process.env.SMOKE_TEST_EMAIL ?? "";

// Pricing — keep in sync with scripts/ai-cost-report.mjs (the one marked spot
// to re-price if analyze-hand moves to Haiku).
const PRICING = {
  "claude-sonnet-4-6": { input: 3 / 1e6, output: 15 / 1e6, cacheRead: 0.3 / 1e6, cacheWrite: 3.75 / 1e6 },
  "claude-haiku-4-5":  { input: 1 / 1e6, output: 5 / 1e6,  cacheRead: 0.1 / 1e6, cacheWrite: 1.25 / 1e6 },
};
const FUNCTION_MODEL = {
  "analyze-session": "claude-sonnet-4-6",
  "analyze-hand": "claude-sonnet-4-6", // ← change if/when migrated to Haiku
};

function requireEnv(name) {
  const v = process.env[name];
  if (!v) { console.error(`✗ Missing required env var: ${name}`); process.exit(2); }
  return v;
}

const DAY = 86_400_000;
const now = Date.now();
const cutoff24h = new Date(now - DAY).toISOString();
const cutoff7d = new Date(now - 7 * DAY).toISOString();
const monthStart = (() => { const d = new Date(now); return new Date(d.getFullYear(), d.getMonth(), 1).toISOString(); })();
const ledgerSince = monthStart < cutoff7d ? monthStart : cutoff7d;

async function sb(path) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!res.ok) throw new Error(`${path.split("?")[0]} HTTP ${res.status}: ${(await res.text().catch(() => "")).slice(0, 200)}`);
  return res;
}

async function sbCount(table, filter) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=id&${filter}`, {
    method: "HEAD",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, Prefer: "count=exact" },
  });
  if (!res.ok) throw new Error(`count ${table} HTTP ${res.status}`);
  return Number(res.headers.get("content-range")?.split("/")[1] ?? 0);
}

function rowCost(r) {
  const p = PRICING[FUNCTION_MODEL[r.function_name] ?? "claude-sonnet-4-6"];
  return (r.input_tokens ?? 0) * p.input + (r.output_tokens ?? 0) * p.output +
    (r.cache_read_tokens ?? 0) * p.cacheRead + (r.cache_write_tokens ?? 0) * p.cacheWrite;
}

// ── Smoke-test runs (last 24h) via the GitHub Actions API ────────────────────
async function smokeStatus() {
  if (!REPO || !GH_TOKEN) return { ok: null, line: "⚠️ smoke check skipped (no GitHub token)" };
  const url = `https://api.github.com/repos/${REPO}/actions/workflows/smoke-test.yml/runs?per_page=100&created=>=${cutoff24h}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${GH_TOKEN}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" },
  });
  if (!res.ok) throw new Error(`GitHub runs HTTP ${res.status}`);
  const runs = (await res.json()).workflow_runs ?? [];
  const done = runs.filter((r) => r.status === "completed");
  const failed = done.filter((r) => r.conclusion !== "success").length;
  const passed = done.length - failed;
  if (done.length === 0) return { ok: false, line: "🔴 smoke test: ZERO runs in 24h — cron dead or workflow disabled" };
  if (failed > 0) return { ok: false, line: `🔴 smoke test: ${failed} FAILED / ${passed} passed (24h)` };
  return { ok: true, line: `✅ smoke test: ${passed}/${passed} green (24h)` };
}

// ── AI spend / cache health from ai_usage_log ─────────────────────────────────
async function aiStatus() {
  const cols = "function_name,called_at,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens";
  const rows = await (await sb(`/rest/v1/ai_usage_log?select=${cols}&called_at=gte.${ledgerSince}&order=called_at.asc`)).json();
  const acc = (since) => rows.filter((r) => r.called_at >= since);
  const sum = (rs) => rs.reduce((a, r) => ({
    calls: a.calls + 1, cost: a.cost + rowCost(r),
    input: a.input + (r.input_tokens ?? 0),
    cacheRead: a.cacheRead + (r.cache_read_tokens ?? 0),
    cacheWrite: a.cacheWrite + (r.cache_write_tokens ?? 0),
  }), { calls: 0, cost: 0, input: 0, cacheRead: 0, cacheWrite: 0 });

  const d1 = sum(acc(cutoff24h)), d7 = sum(acc(cutoff7d)), mtd = sum(acc(monthStart));
  const share = (a) => a.cacheRead / Math.max(1, a.cacheRead + a.input + a.cacheWrite);
  const rate7 = d7.cost / 7;
  const daysToCap = rate7 > 0 ? (CAP - mtd.cost) / rate7 : null;

  const cacheBroken = d7.calls > 5 && d7.cacheRead === 0;
  const lowCache = !cacheBroken && d7.calls > 5 && share(d7) < 0.3;
  const overCap = (mtd.cost / new Date(now).getDate()) * 30 >= CAP;

  let icon = "✅", warn = "";
  if (cacheBroken) { icon = "🔴"; warn = " — CACHE BROKEN (0 cache reads, input cost ~2×)"; }
  else if (overCap) { icon = "🔴"; warn = ` — projected month ≥ $${CAP} cap`; }
  else if (lowCache) { icon = "🟡"; warn = " — low cache hit-rate, check ephemeral cache"; }

  const line = `${icon} AI: ${d1.calls} calls / $${d1.cost.toFixed(2)} yesterday · cache ${(share(d7) * 100).toFixed(0)}% (7d) · ` +
    `$${mtd.cost.toFixed(2)} MTD` + (daysToCap == null ? "" : ` · ~${Math.max(0, daysToCap).toFixed(0)}d to $${CAP} cap`) + warn;
  return { ok: icon === "✅", warnOnly: icon === "🟡", line };
}

// ── Light activity counts (24h) ───────────────────────────────────────────────
async function activityStatus() {
  let smokeUserId = null;
  if (SMOKE_EMAIL) {
    try {
      const res = await sb(`/auth/v1/admin/users?per_page=1000`);
      const users = (await res.json()).users ?? [];
      smokeUserId = users.find((u) => u.email === SMOKE_EMAIL)?.id ?? null;
      var newUsers = users.filter((u) => u.created_at >= cutoff24h && u.email !== SMOKE_EMAIL).length;
    } catch { var newUsers = null; }
  } else {
    try {
      const res = await sb(`/auth/v1/admin/users?per_page=1000`);
      var newUsers = ((await res.json()).users ?? []).filter((u) => u.created_at >= cutoff24h).length;
    } catch { var newUsers = null; }
  }
  const notSmoke = smokeUserId ? `&user_id=neq.${smokeUserId}` : "";
  // sessions.created_at is TEXT (legacy dashboard table) — ISO strings compare
  // lexicographically, so gte works.
  const sessions = await sbCount("sessions", `created_at=gte.${encodeURIComponent(cutoff24h)}${notSmoke}`);
  const hands = await sbCount("hands", `created_at=gte.${encodeURIComponent(cutoff24h)}${notSmoke}`);
  return { line: `📈 yesterday: ${newUsers ?? "?"} new accounts · ${sessions} sessions · ${hands} hands` };
}

async function post(text) {
  if (DRY_RUN || !WEBHOOK) { console.log("── dry run ──\n" + text); return; }
  const res = await fetch(WEBHOOK, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });
  if (!res.ok) throw new Error(`webhook HTTP ${res.status}`);
}

async function main() {
  const [smoke, ai, activity] = await Promise.all([smokeStatus(), aiStatus(), activityStatus()]);
  const allGreen = smoke.ok !== false && (ai.ok || ai.warnOnly);
  const header = allGreen
    ? (ai.warnOnly ? "🟡 TableLab daily" : "☀️ TableLab daily — all green")
    : "🔴 TableLab daily — ATTENTION";
  const date = new Date().toISOString().slice(0, 10);
  await post(`${header} (${date})\n${smoke.line}\n${ai.line}\n${activity.line}`);
  console.log("Digest posted.");
}

main().catch((e) => {
  console.error("Daily digest failed:", e instanceof Error ? e.message : String(e));
  process.exit(1);
});
