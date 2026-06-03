-- Store input/output tokens separately for exact AI cost modeling.
-- Until now only tokens_used (input + output summed) was stored, which mixes the
-- $3/M input rate with the $15/M output rate and makes per-call cost impossible
-- to compute. With input_tokens + output_tokens + the existing
-- cache_read_tokens / cache_write_tokens, cost per call is fully determined:
--   cost = input_tokens   * 3.00/1e6
--        + output_tokens  * 15.00/1e6
--        + cache_read_tokens  * 0.30/1e6
--        + cache_write_tokens * 3.75/1e6
-- (Anthropic's usage.input_tokens counts only UNCACHED input; cached input is in
-- the cache_* columns, so the four columns do not double-count.)
--
-- tokens_used is kept for back-compat. New columns are covered by the existing
-- table GRANTs (grant applies to all columns, including ones added later).

alter table ai_analyses
  add column if not exists input_tokens  integer not null default 0,
  add column if not exists output_tokens integer not null default 0;

alter table ai_hand_analyses
  add column if not exists input_tokens  integer not null default 0,
  add column if not exists output_tokens integer not null default 0;
