# TableLab — Incident Runbook

Solo-operator playbook for production. When something looks wrong, find the **symptom**
below and follow the steps. Keep this file out of `docs/` (it is internal — `docs/` is
served publicly at tablelab.app).

Companion docs: `scripts/SMOKE_TEST.md`, `scripts/AI_COST_MONITOR.md`, and `CLAUDE.md`
(the architecture + footguns reference).

---

## 0. The 30-second health check

Three signals tell you if prod is healthy. If all three are green, relax.

| Signal | Where | Green looks like |
|---|---|---|
| **Daily digest** | Discord ops channel (`ALERT_WEBHOOK`), ~13:21 UTC daily | A message arrives. Its **absence is itself an alert** — monitoring is dead. |
| **Smoke test** | `smoke-test.yml`, twice hourly (`:07/:37`) + deep daily 08:15 UTC | Green checks in GitHub Actions; no 🔴 in the alert channel. |
| **Crashlytics** | Firebase console (Android only) | No new crashes on the **current released build** (filter by version — today `1.5.0+10`). |

> Crashlytics is **release-only by design** (`setCrashlyticsCollectionEnabled(!kDebugMode)`).
> Debug-only asserts never reach it. Always filter by the released version to ignore stale crashes.

**First diagnostic move for almost any backend incident:** run the smoke test locally
with the deep flag — it exercises auth → sessions CRUD → hand FK → a real costed AI call
and asserts the `ai_usage_log` write. It reproduces the whole silent-failure class.

```bash
SUPABASE_URL=https://<project>.supabase.co \
SUPABASE_ANON_KEY=<anon> \
SMOKE_TEST_EMAIL=<synthetic test acct> \
SMOKE_TEST_PASSWORD=<...> \
SMOKE_DEEP=1 \
node scripts/smoke-test.mjs
```

---

## 1. The digest stopped arriving (silent monitoring death)

**This is the worst failure because nothing screams.** No digest at ~13:21 UTC = you are
flying blind, not necessarily that prod is down.

1. Check `daily-digest.yml` runs in GitHub Actions → Actions tab. Look for failed/skipped runs.
2. Common causes, in order:
   - **`SUPABASE_SERVICE_ROLE_KEY` rotated/expired** — the digest needs it (deliberate
     exposure, 2026-06-11). If you rotated it in Supabase → Settings → API, update the
     GitHub secret to match.
   - **`ALERT_WEBHOOK` / `SMOKE_ALERT_WEBHOOK` Discord webhook deleted** — recreate the
     webhook in the channel (keep the `/slack` suffix) and update the secret.
   - **GitHub Actions disabled** (60-day inactivity auto-disable on the repo) — re-enable.
3. Manually trigger it: Actions → daily-digest → "Run workflow".

> The smoke test and digest both post to the **`/slack`-suffixed** Discord webhook. The
> **user-feedback** webhook (`FEEDBACK_WEBHOOK_URL`) is a *separate* channel — never cross them.

---

## 2. Smoke test is red

The smoke test is the canary for the **"200 but writes nothing"** class that uptime pings
can't see. What failed tells you where:

| Failing step | Meaning | Action |
|---|---|---|
| **Auth** | Synthetic account can't log in | Check the test account isn't disabled/password-changed; check Supabase auth is up. |
| **Sessions CRUD** | RLS or table-level write broken | See §3 (GRANT / RLS). Confirm the insert sets `user_id` explicitly (`WITH CHECK user_id = auth.uid()`). |
| **Hand FK / cache-hit shows a new `ai_usage_log` row** | Cache isn't firing → every call costs money | The smoke `hands` row (`SMOKE_HAND_ID = 00000000-0000-4000-8000-000000000001`) is missing — the script self-provisions it, but if the cache upsert FKs to a missing `hands(id)` it fails. See §3. |
| **Deep run: no fresh `ai_usage_log` row after forced call** | `logUsage` insert is silently failing → rate limits read 0 → **unlimited AI spend** | **Highest-urgency silent failure.** Go to §3, check GRANTs on `ai_usage_log`. |

---

## 3. 42501 / "permission denied" / 200-but-no-write (GRANT & RLS)

The signature TableLab footgun. Postgres checks **table-level GRANTs before RLS**, and
`service_role`'s `BYPASSRLS` does **not** grant table/sequence privileges. A table with
only RLS + policies fails every access with `42501` — and because the Edge Functions don't
throw on `.error`, they return **200 while writing nothing**. This silently disables the AI
cache and zeroes the rate-limit count (→ uncapped spend).

**Diagnose:**
1. Re-run smoke test with `SMOKE_DEEP=1` (§0). A failed `ai_usage_log` assertion confirms it.
2. In the Supabase SQL editor, try the write as service_role, or inspect grants:
   ```sql
   select grantee, privilege_type from information_schema.role_table_grants
   where table_name = '<table>';
   ```

**Fix** (paste into the SQL editor — **do NOT `supabase db push`**, migration history is
desynced; still commit the migration file for replayability):
```sql
grant select, insert, update on <table> to service_role, postgres;
grant select on <table> to authenticated;
-- ONLY for serial/bigserial PKs (uuid-default PKs don't need this):
grant usage, select on sequence <table>_<col>_seq to service_role, postgres;
```
Precedent: `20260602_ai_table_grants.sql`, `20260619_feedback.sql`. Follow the
`tournament_listings` / `profiles` pattern for any new table.

> **Schema-then-deploy order is mandatory.** An Edge Function that writes a new column must
> be deployed *after* the column exists, or its insert fails silently.

---

## 4. AI spend climbing toward the $100 cap

The cap binds around **100–150 MAU**. Per-user limits: **20/day** `analyze-hand`,
**5/day** `analyze-session` (cache hits don't count). `rhtk.1234@gmail.com` is exempt.

**Check current spend (local — needs the service-role key, `ai_usage_log` is RLS-scoped):**
```bash
SUPABASE_URL=https://<project>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<...> \
node scripts/ai-cost-report.mjs
```
Zero-secret alternative: paste `scripts/ai-cost-report.sql` into the Supabase SQL editor.

**Read these from the report:**
- **`cache_read_share` ≈ 0 while calls > 5** → the ephemeral system-prompt cache broke;
  input cost ~2×. The system prompt must stay a static `const` with
  `cache_control: { type: "ephemeral" }` — any per-user data injected into it kills caching.
- **One user dominating spend** → likely abuse or a cache miss loop for that user.
- **Days-to-$100 projection** → your runway.

**Levers, cheapest first:**
1. **Verify the cache is actually working** (a broken cache is usually the real cause of a
   spike, not genuine volume) — see §3.
2. **Move `analyze-hand` to Haiku** — the biggest structural cost cut; pushes the cap
   ceiling out materially. Re-price the one marked spot in `ai-cost-report.{sql,mjs}` if you do.
3. **Tighten daily limits** — drop `HAND_DAILY_LIMIT` / `SESSION_DAILY_LIMIT` in the Edge
   Functions and redeploy.
4. **Accept graceful degradation at the cap** — users hitting a limit get a clean 429
   (`"Daily analysis limit reached. Please try again tomorrow."`). Confirm the *global* cap
   also degrades cleanly rather than 500-ing. The app fires `aiRateLimitHit` analytics on 429.

---

## 5. PGRST303 errors reported by users

JWT clock-skew (device clock ahead of Supabase). Already handled: every Supabase call goes
through `withSupabaseRetry<T>()` (`lib/services/supabase_retry.dart`), which refreshes the
session and retries once. **If users still see it**, the cause is a write path that bypassed
the retry wrapper — find the call site and wrap it.

---

## 6. Tournament scraper stopped (weekly Mon 9am UTC)

Tournament Calendar going stale. Almost always the **JWT-verification gotcha**:

- `scrape-tournaments` is authed by `SCRAPE_SECRET` in-function, **not** a user JWT, so it
  must be deployed with gateway verification **OFF**. A bare `supabase functions deploy`
  flips `verify_jwt` back to `true`, and the cron then 401s
  (`UNAUTHORIZED_INVALID_JWT_FORMAT`) at the gateway before the function runs.
- `config.toml` pins `[functions.scrape-tournaments] verify_jwt = false`, but **always
  redeploy with the flag**:
  ```bash
  supabase functions deploy scrape-tournaments --no-verify-jwt
  ```
- Manual trigger to test:
  ```bash
  curl -X POST -H "Authorization: Bearer <SCRAPE_SECRET>" \
    https://<project>.supabase.co/functions/v1/scrape-tournaments
  ```
- This function has **no Discord alerting** — check the function logs in the Supabase dashboard.

---

## 7. Edge Function erroring (general)

All four functions (`analyze-hand`, `analyze-session`, `delete-account`, `submit-feedback`)
report to Discord via `_shared/alert.ts` → `reportError(fn, detail)` → `ALERT_WEBHOOK_URL`.
Alerts never contain user data.

1. Read the alert text — it names the function and failure site.
2. Pull live logs: Supabase dashboard → Edge Functions → the function → Logs. Raw exceptions
   are logged server-side only (users get generic messages).
3. Timeouts: `analyze-session` 120s, `analyze-hand` 50s (both via `Promise.race`). A 504/timeout
   on session analysis usually means too many linked hands — it caps at **3 linked hands**;
   confirm that cap is intact.
4. CORS is locked to `https://tablelab.app` / `https://www.tablelab.app` — do **not** revert to `*`.

---

## 8. A crash spike in Crashlytics

1. Filter to the **current released build** (`1.5.0+10` today) to ignore stale crashes.
2. Known prod-only crash classes (asserts stripped in release) — check these patterns first:
   - **Keyless `ExpansionTile`** writing a `bool` into the shared PageStorage slot, then a
     later keyless scrollable reads it as `double?` and crashes in layout. Fix: give every
     `ExpansionTile` a unique `PageStorageKey`.
   - **Deep-link route crash** — a platform route push with no named-route match hits
     `onUnknownRoute` on null. `MaterialApp.onUnknownRoute` in `main.dart` swallows these;
     do not remove it.
   - **fl_chart on Windows** RangeError — every chart must set `BarTouchData(enabled: false)`
     / `LineTouchData(enabled: false)`.
3. Hotfix path: fix → `flutter analyze --fatal-infos` + `flutter test` → `bash scripts/bump-version.sh X.Y.Z`
   → push `main` + the `vX.Y.Z` tag → CI builds the signed AAB → upload to Play.

---

## 9. User reports data loss / wrong data

1. **Cross-account leakage?** Every user-scoped provider must `ref.watch(authUserIdProvider)`.
   If a user saw another account's data, a provider is missing that watch.
2. **Write didn't show up?** There is **no Realtime** — every write path must
   `ref.invalidate(...)` the relevant provider (`sessionsProvider` / `handsProvider` /
   `readsProvider`). The CSV import path was a past offender; the importer relies on the
   call site to invalidate.
3. **Live session polluting stats?** All stats derive from `completedSessionsProvider`
   (live sessions excluded until finalized). A new aggregation reading raw `sessionsProvider`
   is the bug.

---

## 10. GDPR / privacy / account-deletion request

Legal clock applies — handle promptly.

- Self-serve deletion is the **`delete-account`** Edge Function (verifies JWT, deletes all
  user data in FK order, then deletes the auth user via service role). It alerts on per-table
  failures.
- If a user emails `privacy@` / `support@tablelab.app` (Cloudflare routing): confirm those
  inboxes land somewhere you read daily.
- Data controller of record is **MagpiQ**; company/billing contact `admin@magpiq.com`.

---

## Quick reference — secrets & schedules

**GitHub secrets:** `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
(digest), `SMOKE_TEST_EMAIL`, `SMOKE_TEST_PASSWORD`, `SMOKE_ALERT_WEBHOOK`,
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`.

**Edge Function env vars:** `ALERT_WEBHOOK_URL` (ops), `FEEDBACK_WEBHOOK_URL` (user feedback —
separate channel), `SCRAPE_SECRET`, `ANTHROPIC_API_KEY`.

**Crons (UTC):** smoke `7,37 * * * *` + deep `15 8 * * *` · digest `21 13 * * *` ·
scraper `0 9 * * 1` (Mon).

**Never do:** `supabase db push` (migration history desynced — apply SQL in the editor) ·
revert CORS to `*` · deploy `scrape-tournaments` without `--no-verify-jwt` · put user data
in ops alert text · commit `lib/config/supabase_config.dart` (CI generates it).
