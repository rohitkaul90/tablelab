-- Track cache token usage per AI call for accurate cost modeling.
-- cache_read_tokens: tokens served from Anthropic prompt cache (cheap: $0.30/M)
-- cache_write_tokens: tokens written to cache on first call (moderate: $3.75/M)
-- Allows precise per-call cost calculation separate from regular input tokens.

ALTER TABLE ai_analyses
  ADD COLUMN IF NOT EXISTS cache_read_tokens integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cache_write_tokens integer NOT NULL DEFAULT 0;

ALTER TABLE ai_hand_analyses
  ADD COLUMN IF NOT EXISTS cache_read_tokens integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cache_write_tokens integer NOT NULL DEFAULT 0;
