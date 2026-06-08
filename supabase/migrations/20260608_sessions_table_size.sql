-- Add optional table_size (number of seats, 2–9) to sessions, used for cash
-- games (e.g. 6-max / 8-handed / 9-handed full ring).
--
-- ⚠️ The `sessions` table was created directly in the Supabase dashboard (its
-- base DDL is not in migrations) and the remote migration history is desynced.
-- Do NOT run `supabase db push`. Apply this by pasting it into the Supabase SQL
-- editor and running it directly. This file is committed for replayability.
--
-- Idempotent: safe to run more than once.

alter table public.sessions
  add column if not exists table_size integer;

comment on column public.sessions.table_size is
  'Number of players at the table (2 = heads-up … 9 = full ring). Optional; set on cash sessions.';
