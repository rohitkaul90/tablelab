-- Tester last-active roster — paste into the Supabase SQL editor (zero secrets).
-- One row per account: when they last did anything that writes data, plus
-- lifetime volume. Use during the closed test to spot testers going quiet
-- (nudge them) and to answer Google's production-access engagement questions.
--
-- "Last active" here = last data write (session/hand/AI call), which is a
-- stronger signal than auth.users.last_sign_in_at (sessions persist, so
-- testers rarely re-sign-in). PostHog People (by email) becomes the richer
-- source once testers are on a build with AnalyticsService.identify wired
-- (added 2026-06-11).

select
  u.email,
  to_char(greatest(
    coalesce(s.last_at, '-infinity'::timestamptz),
    coalesce(h.last_at, '-infinity'::timestamptz),
    coalesce(a.last_at, '-infinity'::timestamptz)
  ), 'YYYY-MM-DD HH24:MI') as last_active_utc,
  to_char(u.last_sign_in_at, 'YYYY-MM-DD') as last_sign_in,
  coalesce(s.n, 0) as sessions,
  coalesce(h.n, 0) as hands,
  coalesce(a.n, 0) as ai_calls,
  to_char(u.created_at, 'YYYY-MM-DD') as signed_up
from auth.users u
left join (
  -- sessions.created_at is TEXT (dashboard-created table) — cast to compare
  select user_id, max(created_at::timestamptz) as last_at, count(*) as n
  from public.sessions group by user_id
) s on s.user_id = u.id
left join (
  select user_id, max(created_at) as last_at, count(*) as n
  from public.hands group by user_id
) h on h.user_id = u.id
left join (
  select user_id, max(called_at) as last_at, count(*) as n
  from public.ai_usage_log group by user_id
) a on a.user_id = u.id
order by greatest(
  coalesce(s.last_at, '-infinity'::timestamptz),
  coalesce(h.last_at, '-infinity'::timestamptz),
  coalesce(a.last_at, '-infinity'::timestamptz)
) desc nulls last;
