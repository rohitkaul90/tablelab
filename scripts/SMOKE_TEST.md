# Synthetic smoke test

`scripts/smoke-test.mjs` exercises the **real production paths** end-to-end, on a
schedule, and fails loudly when any of them silently breaks. It exists to catch
the failure class UptimeRobot **cannot** see: an Edge Function (or PostgREST
write) that returns HTTP **200 while writing nothing** — the `42501` GRANT bug,
a broken `logUsage` insert, an RLS regression after a migration.

## What it checks (cheapest → costliest)

1. **Auth** — password sign-in against Supabase Auth.
2. **Sessions CRUD** — insert a throwaway session → read it back → delete it,
   via PostgREST with the user's JWT (so it runs through RLS, like the app).
3. **`analyze-hand` reachable** — calls the function with `forceRefresh:false`
   and a fixed hand id, so after the first warm-up it's a **cache hit = $0**.
   Proves the function is deployed, auth works, and the cache read path is alive.
4. **Full AI write path** (DEEP, daily only — ~$0.034) — calls with
   `forceRefresh:true` to force a real Claude call, then asserts a **fresh row
   appeared in `ai_usage_log`**. This is the smoking-gun check: a forced call
   that 200s but leaves no new log row means the write path is silently broken.

Exit 0 = all green; non-zero fails the CI job (→ GitHub emails you) and, if
`SMOKE_ALERT_WEBHOOK` is set, POSTs a one-line alert to it.

## One-time setup

### 1. Create a dedicated synthetic test account

In Supabase → Authentication → Users → **Add user** (email + password, mark
email confirmed). Do **not** use your personal account — keep smoke-test data
out of your real stats.

- Step 4 forces one uncached Claude call per day. Either:
  - add this account's email to `EXEMPT_EMAILS` in
    `supabase/functions/analyze-hand/index.ts` (then redeploy) so the 20/day
    rate limit never blocks it, **or**
  - leave it non-exempt — one deep run/day is well under the 20/day cap.
- The cheap runs (step 3) are cache hits and **don't** consume rate limit
  (cache check happens before the rate-limit check).

### 2. Add GitHub repo secrets

Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `SUPABASE_URL` | already used by other workflows — reuse it |
| `SUPABASE_ANON_KEY` | already present — reuse it |
| `SMOKE_TEST_EMAIL` | the synthetic account's email |
| `SMOKE_TEST_PASSWORD` | its password |
| `SMOKE_ALERT_WEBHOOK` | *(optional)* Slack/Discord/Telegram-bridge incoming webhook URL |

> The workflow only reads these as **secrets**, never `vars` — keep the password
> out of plaintext config.

### 3. Warm the cache once

Trigger the workflow manually (Actions → Smoke Test → Run workflow). The first
step-3 call is an uncached Claude call (~$0.034, one time); every cheap run after
that is a free cache hit.

## Schedule

- Every **30 min**: cheap check (auth + sessions + cache-hit analyze-hand), $0.
- **08:15 UTC daily**: deep check (forces the AI write path), ~$0.034/day.

Tune the cron in `.github/workflows/smoke-test.yml`.

## Run locally

```bash
SUPABASE_URL=https://xxxx.supabase.co \
SUPABASE_ANON_KEY=... \
SMOKE_TEST_EMAIL=smoke@tablelab.app \
SMOKE_TEST_PASSWORD=... \
SMOKE_DEEP=1 \
node scripts/smoke-test.mjs
```

## Alerting

Failure surfaces two ways:

1. **GitHub** emails the repo owner on any failed scheduled workflow run (on by
   default — no setup).
2. **Webhook** (optional): set `SMOKE_ALERT_WEBHOOK` to any incoming-webhook URL
   that accepts `{ "text": "..." }` (Slack, Discord with `/slack` suffix,
   Mattermost, a Telegram bridge, etc.).

## Gotchas

- GitHub **disables scheduled workflows after 60 days of repo inactivity** — a
  push re-arms them. Active development means this rarely bites.
- Scheduled-cron timing on GitHub is best-effort (can lag minutes under load) —
  fine for monitoring, don't treat run times as exact.
- If you rotate the test account's password, update the secret.
- The fixed `SMOKE_HAND_ID` keeps step 3 free; don't randomize it.
