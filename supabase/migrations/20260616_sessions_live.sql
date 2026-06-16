-- Live session recorder: lets a session be recorded in real time (running
-- clock, rebuys/add-ons, current stack) and finalized in place into a normal
-- completed session.
--
--   status        'completed' (every historically logged session) or 'live'
--                 while in progress. Stats/bankroll exclude 'live' rows.
--   started_at    full sit-down timestamp — the clock anchor (survives an app
--                 kill; start_time/end_time/duration_minutes are derived from
--                 it on finalize).
--   buyin_events  timestamped buy-in/rebuy/add-on history; `buy_in` stays the
--                 running SUM of these amounts (keeps stats/back-compat working).
--   current_stack last-entered live stack, feeding the live net estimate.
--
-- It also adds session expense + break tracking (used by both the live recorder
-- and the manual log form):
--   expense_events  timestamped expenses {amount, category, note, ts}. Kept
--                   SEPARATE from profit_loss — the app shows a derived "net
--                   after expenses" so win-rate / BB-100 / variance stay pure.
--   break_minutes   minutes spent on break; duration_minutes stays the PLAYED
--                   time (gross − breaks) so existing hourly stats are unchanged.
--   break_started_at set while a live session is paused (null otherwise) so the
--                   break clock survives an app kill.
--
-- ⚠️ The `sessions` table was created directly in the Supabase dashboard (its
-- base DDL is not in migrations) and the remote migration history is desynced.
-- Do NOT run `supabase db push`. Apply this by pasting it into the Supabase SQL
-- editor and running it directly. This file is committed for replayability.
--
-- The existing table already has the needed GRANTs (no new table/sequence), so
-- enabling these columns needs no additional grants.
--
-- Idempotent: safe to run more than once.

alter table public.sessions
  add column if not exists status text not null default 'completed',
  add column if not exists started_at timestamptz,
  add column if not exists buyin_events jsonb,
  add column if not exists current_stack numeric,
  add column if not exists expense_events jsonb,
  add column if not exists break_minutes integer,
  add column if not exists break_started_at timestamptz;

comment on column public.sessions.status is
  'completed (default) or live while the session is being recorded in real time. Stats/bankroll exclude live rows until finalized.';
comment on column public.sessions.started_at is
  'Full sit-down timestamp; the live clock anchor. start_time/end_time/duration_minutes are derived from it on finalize.';
comment on column public.sessions.buyin_events is
  'JSONB array of {amount, ts, kind} where kind in (buyin, rebuy, addon). buy_in is the running sum of these amounts.';
comment on column public.sessions.current_stack is
  'Last-entered current stack while live; feeds the live net estimate (stack - total bought in).';
comment on column public.sessions.expense_events is
  'JSONB array of {amount, category, note, ts}. Tracked separately from profit_loss; the app shows a derived net-after-expenses.';
comment on column public.sessions.break_minutes is
  'Minutes on break. duration_minutes stays PLAYED time (gross - breaks); break_minutes is kept as metadata.';
comment on column public.sessions.break_started_at is
  'Set while a live session is paused (null otherwise) so the break clock survives an app kill.';
