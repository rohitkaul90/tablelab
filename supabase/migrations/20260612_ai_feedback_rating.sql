-- Thumbs up/down on AI analyses (trust pack). rating: 1 = up, -1 = down.
-- Ratings double as the seed of the future eval dataset (Phase 2 harness).
--
-- ⚠️ Apply via the Supabase SQL editor — migration history is desynced, do
-- NOT run `supabase db push`. Commit this file for replayability.
--
-- Note the GRANTs gotcha: Postgres checks table-level GRANTs BEFORE RLS, so
-- `authenticated` needs an explicit column-scoped UPDATE grant here (SELECT
-- was granted in 20260602_ai_table_grants). The client updates these columns
-- directly; no Edge Function involved.

alter table public.ai_hand_analyses
  add column if not exists rating smallint check (rating in (-1, 1)),
  add column if not exists rated_at timestamptz;

alter table public.ai_analyses
  add column if not exists rating smallint check (rating in (-1, 1)),
  add column if not exists rated_at timestamptz;

grant update (rating, rated_at) on public.ai_hand_analyses to authenticated;
grant update (rating, rated_at) on public.ai_analyses to authenticated;

drop policy if exists "Users can rate own hand analyses" on public.ai_hand_analyses;
create policy "Users can rate own hand analyses"
  on public.ai_hand_analyses for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can rate own session analyses" on public.ai_analyses;
create policy "Users can rate own session analyses"
  on public.ai_analyses for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
