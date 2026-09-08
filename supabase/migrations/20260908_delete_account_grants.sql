-- delete-account's explicit per-table sweep runs as service_role, but the
-- GRANTs-before-RLS gotcha (CLAUDE.md) applied to the legacy / non-AI tables:
-- service_role had SELECT only on sessions + hands (20260611) and NO privileges
-- at all on player_reads, rake_presets, profiles (profiles grants only
-- `authenticated`). Every delete-account call therefore 42501'd on all five
-- tables and fired five Discord alerts (first observed 2026-09-08). The user's
-- data was still removed because each table has ON DELETE CASCADE from
-- auth.users and the final auth.admin.deleteUser succeeded — but the explicit
-- sweep is the belt-and-braces GDPR path and must not silently fail.
--
-- ⚠️ Applied directly via the SQL editor on 2026-09-08 (migration history is
-- desynced — do NOT `supabase db push`; this file exists for replayability).

grant delete on table public.sessions, public.hands, public.player_reads,
  public.rake_presets, public.profiles to service_role;
grant select on table public.player_reads, public.rake_presets, public.profiles
  to service_role;
