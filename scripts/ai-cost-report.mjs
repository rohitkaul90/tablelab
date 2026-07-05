#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// TableLab AI cost / cache monitor (formatted report).
//
// Reads the append-only spend ledger (ai_usage_log) and prints spend, cache
// health, per-user economics, and a days-to-cap projection. The Anthropic
// console shows total spend with an $80/$100 alert but CAN'T show cache hit-rate
// or per-user cost — this does. See also scripts/ai-cost-report.sql for the
// zero-secret SQL-editor version.
//
// ⚠️ Needs the SERVICE-ROLE key (not anon): ai_usage_log is RLS-scoped per user,
// so aggregating across all users requires bypassing RLS. Keep that key OUT of
// CI unless you accept the exposure — run this locally, or use the .sql file.
//
// Env:
//   SUPABASE_URL                  https://xxxx.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY     service-role key (Supabase → Settings → API)
//   AI_SPEND_CAP                  optional, default 100 (the Anthropic hard cap, $)
//
// Flags:  --json   emit machine-readable JSON instead of the text report
//
// Run:  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/ai-cost-report.mjs
// ─────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = requireEnv("SUPABASE_URL").replace(/\/+$/, "");
const SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const CAP = Number(process.env.AI_SPEND_CAP ?? "100");
const AS_JSON = process.argv.includes("--json");

// Per-token pricing. Both Edge Functions use Sonnet 4.6 today; if analyze-hand
// later moves to Haiku 4.5, give it its own entry and price by function_name.
const PRICING = {
  "claude-sonnet-4-6": { input: 3 / 1e6, output: 15 / 1e6, cacheRead: 0.3 / 1e6, cacheWrite: 3.75 / 1e6 },
  "claude-haiku-4-5":  { input: 1 / 1e6, output: 5 / 1e6,  cacheRead: 0.1 / 1e6, cacheWrite: 1.25 / 1e6 },
};
const FUNCTION_MODEL = {
  "analyze-session": "claude-sonnet-4-6",
  "analyze-hand": "claude-sonnet-4-6", // ← change to "claude-haiku-4-5" if/when migrated
};

function requireEnv(name) {
  const v = process.env[name];
  if (!v) { console.error(`✗ Missing required env var: ${name}`); process.exit(2); }
  return v;
}

function rowCost(r) {
  const model = FUNCTION_MODEL[r.function_name] ?? "claude-sonnet-4-6";
  const p = PRICING[model];
  return (
    (r.input_tokens ?? 0) * p.input +
    (r.output_tokens ?? 0) * p.output +
    (r.cache_read_tokens ?? 0) * p.cacheRead +
    (r.cache_write_tokens ?? 0) * p.cacheWrite
  );
}

// ── Fetch the full ledger (paginated; PostgREST caps pages at 1000) ───────────
async function fetchAllRows() {
  const cols = "user_id,function_name,called_at,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens";
  const pageSize = 1000;
  const rows = [];
  for (let from = 0; ; from += pageSize) {
    const to = from + pageSize - 1;
    const res = await fetch(`${SUPABASE_URL}/rest/v1/ai_usage_log?select=${cols}&order=called_at.asc`, {
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        Range: `${from}-${to}`,
        "Range-Unit": "items",
      },
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`ai_usage_log read HTTP ${res.status}: ${body.slice(0, 200)}`);
    }
    const page = await res.json();
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return rows;
}

// ── Aggregate ─────────────────────────────────────────────────────────────────
function analyze(rows) {
  const now = Date.now();
  const DAY = 86_400_000;
  const since = (d) => now - d * DAY;
  const monthStart = (() => { const dt = new Date(now); return new Date(dt.getFullYear(), dt.getMonth(), 1).getTime(); })();

  const blank = () => ({ calls: 0, cost: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
  const add = (acc, r, c) => {
    acc.calls++; acc.cost += c;
    acc.input += r.input_tokens ?? 0; acc.output += r.output_tokens ?? 0;
    acc.cacheRead += r.cache_read_tokens ?? 0; acc.cacheWrite += r.cache_write_tokens ?? 0;
  };

  const all = blank(), w24 = blank(), w7 = blank(), w30 = blank(), mtd = blank();
  const byFn = new Map(), byUser = new Map(), byDay = new Map();
  const users = new Set();

  for (const r of rows) {
    const c = rowCost(r);
    const t = new Date(r.called_at).getTime();
    add(all, r, c);
    if (t >= since(1)) add(w24, r, c);
    if (t >= since(7)) add(w7, r, c);
    if (t >= since(30)) add(w30, r, c);
    if (t >= monthStart) add(mtd, r, c);
    users.add(r.user_id);

    if (!byFn.has(r.function_name)) byFn.set(r.function_name, blank());
    add(byFn.get(r.function_name), r, c);

    if (!byUser.has(r.user_id)) byUser.set(r.user_id, { ...blank(), calls24h: 0 });
    const u = byUser.get(r.user_id); add(u, r, c); if (t >= since(1)) u.calls24h++;

    if (t >= since(14)) {
      const day = new Date(r.called_at).toISOString().slice(0, 10);
      if (!byDay.has(day)) byDay.set(day, blank());
      add(byDay.get(day), r, c);
    }
  }

  const cacheShare = (a) => a.cacheRead / Math.max(1, a.cacheRead + a.input + a.cacheWrite);

  const avgDaily7d = w7.cost / 7;
  const dayOfMonth = new Date(now).getDate();
  const daysInMonth = new Date(new Date(now).getFullYear(), new Date(now).getMonth() + 1, 0).getDate();

  return {
    distinctUsers: users.size,
    all, w24, w7, w30, mtd,
    cacheShareAll: cacheShare(all),
    cacheShare7d: cacheShare(w7),
    // 0 reads is only "broken" if there are also 0 WRITES: writes prove the
    // cache is engaged; 0 reads with writes is just sparse traffic (the ~5min
    // ephemeral TTL vs calls that never cluster within one window).
    cacheEngaged: all.cacheWrite > 0,
    cacheBroken: all.calls > 5 && all.cacheRead === 0 && all.cacheWrite === 0,
    byFunction: [...byFn.entries()].map(([k, v]) => ({ fn: k, ...v, cacheShare: cacheShare(v) }))
      .sort((a, b) => b.cost - a.cost),
    topUsers: [...byUser.entries()].map(([k, v]) => ({ user: k, ...v }))
      .sort((a, b) => b.cost - a.cost).slice(0, 20),
    daily: [...byDay.entries()].map(([day, v]) => ({ day, ...v })).sort((a, b) => b.day.localeCompare(a.day)),
    projection: {
      cap: CAP,
      avgDaily7d,
      projectedMonthFromMtd: dayOfMonth > 0 ? (mtd.cost / dayOfMonth) * daysInMonth : 0,
      projectedMonthFrom7dRate: avgDaily7d * 30,
      daysToCapAt7dRate: avgDaily7d > 0 ? CAP / avgDaily7d : null,
    },
  };
}

// ── Render ────────────────────────────────────────────────────────────────────
const usd = (n) => `$${n.toFixed(4)}`;
const pct = (n) => `${(n * 100).toFixed(1)}%`;
const k = (n) => n.toLocaleString("en-US");

function render(a) {
  const L = [];
  L.push(`TableLab AI cost report — ${new Date().toISOString()}`);
  L.push("");
  L.push("SPEND");
  L.push(`  all-time   ${usd(a.all.cost)}  (${k(a.all.calls)} calls, ${a.distinctUsers} users)`);
  L.push(`  last 24h   ${usd(a.w24.cost)}  (${k(a.w24.calls)} calls)`);
  L.push(`  last 7d    ${usd(a.w7.cost)}  (${k(a.w7.calls)} calls)`);
  L.push(`  last 30d   ${usd(a.w30.cost)}  (${k(a.w30.calls)} calls)`);
  L.push("");
  L.push("CACHE HEALTH");
  L.push(`  read share (all-time)  ${pct(a.cacheShareAll)}   read share (7d)  ${pct(a.cacheShare7d)}`);
  if (a.cacheBroken) L.push("  ⚠ CACHE NOT ENGAGED — 0 cache_read AND 0 cache_write across all calls. cache_control isn't applying; input cost is ~2×.");
  else if (a.cacheShare7d < 0.3 && a.w7.calls > 5) {
    L.push(a.cacheEngaged
      ? "  ℹ Low cache reads (7d) — likely sparse traffic (calls > 5min apart); cache IS engaged (writes happening)."
      : "  ⚠ Low cache hit-rate (7d) — investigate the ephemeral system-prompt cache.");
  }
  L.push("");
  L.push("BY FUNCTION");
  for (const f of a.byFunction) {
    L.push(`  ${f.fn.padEnd(16)} ${usd(f.cost).padStart(10)}  ${String(f.calls).padStart(5)} calls  avg ${usd(f.cost / Math.max(1, f.calls))}  cache ${pct(f.cacheShare)}`);
  }
  L.push("");
  L.push("TOP SPENDERS");
  for (const u of a.topUsers.slice(0, 8)) {
    L.push(`  ${u.user.slice(0, 8)}…  ${usd(u.cost).padStart(10)}  ${String(u.calls).padStart(4)} calls  (${u.calls24h} in 24h)`);
  }
  L.push("");
  L.push(`PROJECTION (cap $${a.projection.cap})`);
  L.push(`  month-to-date           ${usd(a.mtd.cost)}`);
  L.push(`  projected month (MTD)   ${usd(a.projection.projectedMonthFromMtd)}`);
  L.push(`  projected month (7d)    ${usd(a.projection.projectedMonthFrom7dRate)}`);
  L.push(`  days to $${a.projection.cap} at 7d rate  ${a.projection.daysToCapAt7dRate == null ? "n/a (no recent spend)" : a.projection.daysToCapAt7dRate.toFixed(1)}`);
  const proj = Math.max(a.projection.projectedMonthFromMtd, a.projection.projectedMonthFrom7dRate);
  if (proj >= a.projection.cap) L.push(`  🔴 Projected month exceeds the $${a.projection.cap} cap.`);
  else if (proj >= a.projection.cap * 0.8) L.push(`  🟡 Projected month is within 80% of the $${a.projection.cap} cap.`);
  return L.join("\n");
}

async function main() {
  const rows = await fetchAllRows();
  const a = analyze(rows);
  if (AS_JSON) console.log(JSON.stringify(a, null, 2));
  else console.log(render(a));
}

main().catch((e) => {
  console.error("AI cost report failed:", e instanceof Error ? e.message : String(e));
  process.exit(1);
});
