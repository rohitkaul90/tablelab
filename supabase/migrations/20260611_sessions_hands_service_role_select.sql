-- service_role had NO SELECT on the dashboard-created legacy tables (sessions,
-- hands) — the GRANTs-before-RLS gotcha (see CLAUDE.md): BYPASSRLS does not
-- include table privileges, and these tables predate the migration workflow so
-- they never got the explicit grants the 20260602 fix gave the AI tables.
-- Surfaced 2026-06-11 by the daily-digest workflow (403 on a service-role
-- count of sessions). Read-only is all current service-role consumers need;
-- Edge Functions read sessions/hands as the authenticated user.
--
-- ⚠️ Applied directly via psql on 2026-06-11 (migration history is desynced —
-- do NOT `supabase db push`; this file exists for replayability).

grant select on table public.sessions to service_role;
grant select on table public.hands to service_role;
