-- Append-only token ledger on ai_usage_log.
--
-- Token columns previously lived ONLY on the cache rows (ai_analyses /
-- ai_hand_analyses), which are OVERWRITTEN on re-analysis (upsert onConflict) —
-- so summing them undercounts real spend. ai_usage_log has one row per call and
-- is never overwritten, making it the correct source for an accurate, append-only
-- spend ledger. logUsage() in both Edge Functions writes these per call.

alter table ai_usage_log
  add column if not exists input_tokens        integer not null default 0,
  add column if not exists output_tokens       integer not null default 0,
  add column if not exists cache_read_tokens   integer not null default 0,
  add column if not exists cache_write_tokens  integer not null default 0;
