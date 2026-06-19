-- In-app user feedback (Bug / Idea / Praise / Other) captured by the
-- `submit-feedback` Edge Function. Discord is the notification layer; this table
-- is the durable system of record (queryable, backloggable, daily-digest count).
--
-- ⚠️ Apply via the Supabase SQL editor — migration history is desynced, do NOT
-- run `supabase db push`. Commit this file for replayability.
--
-- GRANTs gotcha (CLAUDE.md): Postgres checks table-level GRANTs BEFORE RLS, and
-- service_role's BYPASSRLS does NOT include table privileges. Without the grants
-- below every insert 42501s — and because the Edge Function logs the error but
-- still returns 200, it would fail silently. uuid-default PK → no sequence grant.

create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete set null,
  email       text,                  -- only set when the user opts into follow-up
  category    text not null check (category in ('bug', 'idea', 'praise', 'other')),
  message     text not null,
  rating      smallint check (rating between 1 and 5),
  app_version text,
  platform    text,                  -- 'android' | 'web' | 'ios' | 'windows' | …
  created_at  timestamptz not null default now()
);

alter table public.feedback enable row level security;

-- Writes happen server-side with the service-role client (user_id scoped
-- explicitly in the function) — no client INSERT policy needed.
grant select, insert on public.feedback to service_role, postgres;

-- Let a signed-in user read back their own submissions (optional future UI).
grant select on public.feedback to authenticated;
drop policy if exists "Users can read own feedback" on public.feedback;
create policy "Users can read own feedback"
  on public.feedback for select
  using (auth.uid() = user_id);

create index if not exists feedback_created_at_idx on public.feedback (created_at desc);
