-- ─────────────────────────────────────────────────────────────────────────────
-- TableLab AI cost / cache monitor — run in the Supabase SQL editor.
--
-- ai_usage_log is the append-only spend ledger (one row per Claude call, never
-- overwritten). The Anthropic console shows TOTAL spend with an $80/$100 alert,
-- but can't tell you cache hit-rate, per-user economics, or days-to-cap. This
-- does. Run the whole file (the editor shows the last result), or highlight a
-- single query and run just that.
--
-- PRICING (per token, Sonnet 4.6 — the model BOTH Edge Functions use today):
--   input $3 / output $15 / cache-read $0.30 / cache-write $3.75 per MTok.
--   If analyze-hand later moves to Haiku 4.5 (input $1 / output $5 / cache-read
--   $0.10 / cache-write $1.25), branch the cost expression on function_name.
-- The reusable cost expression is inlined below as:
--   (input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Spend summary: all-time + rolling windows + cache share ────────────────
-- The headline. cache_read_share near 0 with calls > 5 = prompt caching is
-- BROKEN (silently doubling input cost) — the exact failure CLAUDE.md warns of.
with priced as (
  select
    called_at,
    user_id,
    (input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6 as cost,
    input_tokens, output_tokens, cache_read_tokens, cache_write_tokens
  from ai_usage_log
)
select
  count(*)                                              as calls_all_time,
  round(sum(cost)::numeric, 4)                          as spend_all_time,
  round(sum(cost) filter (where called_at >= now() - interval '24 hours')::numeric, 4) as spend_24h,
  round(sum(cost) filter (where called_at >= now() - interval '7 days')::numeric, 4)   as spend_7d,
  round(sum(cost) filter (where called_at >= now() - interval '30 days')::numeric, 4)  as spend_30d,
  count(distinct user_id)                               as distinct_users,
  -- fraction of prompt tokens served from cache (cheap) vs paid input + cache writes
  round(
    sum(cache_read_tokens)::numeric
    / nullif(sum(cache_read_tokens + input_tokens + cache_write_tokens), 0), 3
  )                                                     as cache_read_share
from priced;

-- ── 2. Per-function breakdown ─────────────────────────────────────────────────
select
  function_name,
  count(*)                                              as calls,
  round(sum((input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6)::numeric, 4) as spend,
  round(avg((input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6)::numeric, 5) as avg_cost_per_call,
  sum(input_tokens)                                     as input_tokens,
  sum(output_tokens)                                    as output_tokens,
  sum(cache_read_tokens)                                as cache_read_tokens,
  sum(cache_write_tokens)                               as cache_write_tokens
from ai_usage_log
group by function_name
order by spend desc;

-- ── 3. Cache health (last 7 days) ─────────────────────────────────────────────
-- If cache_read_tokens ≈ 0 here, the ephemeral system-prompt cache isn't being
-- hit — input cost is ~full price on every call. Investigate the Edge Function.
select
  function_name,
  count(*)                          as calls_7d,
  sum(cache_read_tokens)            as cache_read,
  sum(cache_write_tokens)           as cache_write,
  sum(input_tokens)                 as uncached_input,
  round(
    sum(cache_read_tokens)::numeric
    / nullif(sum(cache_read_tokens + input_tokens + cache_write_tokens), 0), 3
  )                                 as cache_read_share
from ai_usage_log
where called_at >= now() - interval '7 days'
group by function_name
order by function_name;

-- ── 4. Top spenders (per user, all-time) ──────────────────────────────────────
-- Validates the freemium allowance math and surfaces abuse before launch.
select
  user_id,
  count(*)                                              as calls,
  round(sum((input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6)::numeric, 4) as spend,
  count(*) filter (where called_at >= now() - interval '24 hours') as calls_24h
from ai_usage_log
group by user_id
order by spend desc
limit 20;

-- ── 5. Daily trend (last 14 days) ─────────────────────────────────────────────
select
  date_trunc('day', called_at)::date                   as day,
  count(*)                                              as calls,
  round(sum((input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6)::numeric, 4) as spend
from ai_usage_log
where called_at >= now() - interval '14 days'
group by 1
order by 1 desc;

-- ── 6. Days-to-cap projection (vs $100 Anthropic monthly hard limit) ──────────
-- Projects this calendar month from month-to-date run-rate, and gives a
-- 7-day-rate monthly projection + days-until-$100 at the current 7d pace.
with rates as (
  select
    sum((input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6)
      filter (where called_at >= date_trunc('month', now()))                  as mtd_spend,
    sum((input_tokens*3 + output_tokens*15 + cache_read_tokens*0.30 + cache_write_tokens*3.75)/1e6)
      filter (where called_at >= now() - interval '7 days') / 7.0             as avg_daily_7d
  from ai_usage_log
)
select
  round(mtd_spend::numeric, 4)                                                as month_to_date,
  round((extract(day from now()))::numeric, 0)                               as day_of_month,
  -- linear projection of the full month from MTD run-rate
  round((mtd_spend / nullif(extract(day from now()), 0)
         * extract(day from (date_trunc('month', now()) + interval '1 month' - interval '1 day')))::numeric, 2)
                                                                             as projected_month_from_mtd,
  round((avg_daily_7d * 30)::numeric, 2)                                      as projected_month_from_7d_rate,
  case when avg_daily_7d > 0
       then round((100.0 / avg_daily_7d)::numeric, 1)
       else null end                                                         as days_to_$100_at_7d_rate
from rates;
