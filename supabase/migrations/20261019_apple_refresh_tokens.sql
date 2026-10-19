-- Sign in with Apple refresh tokens, held ONLY so delete-account can revoke
-- them. App Store Review Guideline 5.1.1(v): an app offering Sign in with Apple
-- must revoke the user's Apple tokens when they delete their account; Supabase's
-- admin deleteUser does not call Apple's /auth/revoke, and Apple's revoke
-- endpoint needs a refresh (or access) token — which only exists after the
-- `apple-link` Edge Function exchanges the sign-in authorization code.
--
-- ⚠️ Apply via the Supabase SQL editor — migration history is desynced, do NOT
-- run `supabase db push`. Commit this file for replayability.
-- Schema-then-deploy: apply this BEFORE deploying `apple-link` / `delete-account`.
--
-- GRANTs gotcha (CLAUDE.md): Postgres checks table-level GRANTs BEFORE RLS and
-- service_role's BYPASSRLS does NOT include table privileges. Service-role only:
-- `authenticated` gets no grant and no policy — the token is a bearer secret
-- that the client must never read back. uuid PK → no sequence grant needed.

create table if not exists public.apple_refresh_tokens (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  refresh_token text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.apple_refresh_tokens enable row level security;

grant select, insert, update, delete on public.apple_refresh_tokens to service_role, postgres;
