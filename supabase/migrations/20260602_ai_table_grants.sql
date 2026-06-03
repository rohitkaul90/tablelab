-- ── AI table privileges ───────────────────────────────────────────────────────
-- ai_analyses, ai_hand_analyses, and ai_usage_log were created with RLS enabled
-- and policies, but NO table-level GRANTs (unlike profiles / tournament_listings).
-- Postgres checks GRANTs BEFORE RLS, and service_role's BYPASSRLS does not include
-- table privileges — so every read/write failed with:
--   42501  permission denied for table ai_analyses
-- This silently broke usage logging, the AI result cache, and (because the
-- rate-limit count read 0 rows) the per-user daily AI limits.
--
-- The Edge Functions (analyze-session / analyze-hand) access these tables with the
-- service_role client after verifying the user, so grant it full access. postgres
-- gets full access for admin/cascade operations. The Flutter app does not read
-- these tables directly today, but the RLS policies target authenticated, so grant
-- read access to keep those policies usable.

grant all privileges on table ai_analyses, ai_hand_analyses, ai_usage_log to service_role;
grant all privileges on table ai_analyses, ai_hand_analyses, ai_usage_log to postgres;
grant select on table ai_analyses, ai_hand_analyses, ai_usage_log to authenticated;

-- ai_usage_log.id is bigserial, so INSERT calls nextval() on its sequence.
-- Sequence privileges are separate from table privileges — without this, inserts
-- fail with "permission denied for sequence ai_usage_log_id_seq". (The analyses
-- tables use uuid defaults, so they need no sequence grant.)
grant usage, select on sequence ai_usage_log_id_seq to service_role, postgres;
