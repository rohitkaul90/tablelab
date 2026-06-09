# AI cost / cache monitor

Two views over `ai_usage_log` (the append-only Claude-spend ledger) that the
Anthropic console can't give you: **cache hit-rate**, **per-user economics**, and
**days-to-cap projection**. This is the dataset that decides monetization timing
(the $100 cap binds at ~100–150 MAU).

| File | Use it for | Secrets |
|---|---|---|
| `ai-cost-report.sql` | Quick ad-hoc look in the Supabase SQL editor | **None** — runs as the dashboard |
| `ai-cost-report.mjs` | Formatted/automatable report, JSON output | Service-role key |

## Why the service-role key (for the script)

`ai_usage_log` is RLS-scoped per user (`auth.uid() = user_id`). A spend monitor
must aggregate across **all** users, which means bypassing RLS — only the
**service-role** key can. Treat that key like a password:

- **Run it locally** (or from a trusted box), not in public CI. Anyone with the
  service-role key has full read/write to every table.
- If you don't want to handle the key at all, use **`ai-cost-report.sql`** — the
  SQL editor already runs with full privileges, so there's no key to manage.

## Pricing assumption

Both Edge Functions call **Sonnet 4.6** today, so cost is priced at Sonnet rates
(input $3 / output $15 / cache-read $0.30 / cache-write $3.75 per MTok). If you
later move `analyze-hand` to Haiku 4.5 (per the monetization plan), update the
one `FUNCTION_MODEL` entry in `ai-cost-report.mjs` and the cost `CASE` in the
`.sql` — both have a comment marking the spot.

## What it reports

- **Spend** — all-time + rolling 24h / 7d / 30d.
- **Cache health** — `cache_read_share`. If it's ~0 with calls > 5, the ephemeral
  system-prompt cache is broken and input cost is ~2× what it should be (the
  silent failure mode flagged in CLAUDE.md). The script prints a ⚠ for this.
- **By function** — calls, spend, avg cost/call, cache share.
- **Top spenders** — validates the freemium allowance math; surfaces abuse.
- **Projection** — projected month (from MTD run-rate and from the 7-day rate)
  and days-until-$100 at the current pace. Prints 🟡 at 80% of cap, 🔴 over.

## Run the SQL version

Supabase → SQL editor → paste `ai-cost-report.sql`. Run the whole file (the
editor shows the last result) or highlight one query and run just that.

## Run the script

```bash
SUPABASE_URL=https://xxxx.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
node scripts/ai-cost-report.mjs

# machine-readable:
... node scripts/ai-cost-report.mjs --json

# override the cap (default $100):
AI_SPEND_CAP=80 ... node scripts/ai-cost-report.mjs
```

## Cadence

Run it weekly (and any time the Anthropic console alert fires) to catch a cache
regression or a runaway user early. If you later want it automated, the JSON
output (`--json`) feeds cleanly into the daily health digest (checklist item #7).
