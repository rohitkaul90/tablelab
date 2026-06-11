# Database Backup & Restore Runbook

Why this exists: TableLab is a financial-data app on Supabase free tier (no
automated backups), the repo cannot rebuild the schema (3 tables were created
in the dashboard and migration history is desynced — see CLAUDE.md), and an
untested backup is a hope, not a plan.

## Taking a backup

```powershell
.\scripts\db-backup.ps1
```

- Reads the DB password from `launch/db-password.txt` (gitignored) or
  `$env:SUPABASE_DB_PASSWORD`. Find/reset it in Supabase dashboard →
  Project Settings → Database.
- Writes to `%USERPROFILE%\TableLabBackups\<timestamp>\` — deliberately
  **outside the repo**. Dumps contain user emails and bankroll data; the repo
  is public. **Never commit a dump, never point `-OutRoot` inside the repo.**
- Uses the direct connection (IPv6). That path proved flaky on this network
  (worked, then timed out); the reliable fallback is the session pooler —
  **this project's pooler is `aws-1-us-west-2.pooler.supabase.com`**:
  `.\scripts\db-backup.ps1 -PoolerHost aws-1-us-west-2.pooler.supabase.com`
  (A wrong-region pooler fails harmlessly with "tenant/user not found".)

What's in a backup:

| File | Contents | Restorable where |
|---|---|---|
| `schema-public.sql` | public DDL incl. RLS policies + GRANTs | new Supabase project or drill cluster |
| `data.sql` | data for `public` + `auth` schemas | same |
| `auth-schema-drill-only.sql` | auth DDL, owners/privileges stripped | **drill cluster only** — never apply to a real Supabase project (auth is Supabase-managed there) |
| `row-counts.txt` | prod row counts + policy count | verification manifest for the drill |

Cadence: daily-ish while data volume is small; on Supabase Pro, the dashboard
daily backups become primary and this becomes the weekly offline backstop.

## Restore drill (verify a backup actually restores)

```powershell
.\scripts\db-restore-verify.ps1            # newest backup
.\scripts\db-restore-verify.ps1 -BackupDir "$env:USERPROFILE\TableLabBackups\2026-06-11_1530"
```

Builds a throwaway Postgres 17 cluster on port 5433 (never touches the
installed service), creates the Supabase roles (`anon`, `authenticated`,
`service_role`, …) and `extensions` schema, applies auth scaffold → public
schema (strict) → data (strict, FK triggers disabled during load), then
compares every table's row count and the policy count against the prod
manifest. Prints `DRILL PASSED` / `DRILL FAILED`. Cluster is deleted unless
`-KeepCluster` is passed (then connect with
`psql -h localhost -p 5433 -U postgres -d tablelab_drill` to poke around).

**Re-drill triggers** — run the drill again when any of these happen,
otherwise ~every 6 months:

- major schema change (new tables, RLS overhaul)
- Postgres major-version bump on Supabase's side
- moving to Supabase Pro (then also drill the dashboard-restore path once)
- the backup script or this runbook changes

## Real disaster recovery (prod is gone or corrupted)

1. Create a fresh Supabase project (same region). Auth/storage schemas exist
   out of the box — do **not** apply `auth-schema-drill-only.sql`.
2. Apply `schema-public.sql` via the SQL editor or
   `psql <new-conn-string> -f schema-public.sql`.
3. Load data: `psql <new-conn-string> -c "set session_replication_role = replica" -f data.sql`.
   (`auth.users` rows restore into the existing auth schema, which keeps every
   `user_id` FK valid. Users keep their passwords — hashes live in `auth.users`.)
4. Re-check the GRANTs gotcha from CLAUDE.md: confirm `service_role` +
   `authenticated` grants survived (`row-counts.txt`'s drill twin is the
   grants INFO line; in prod run the smoke test).
5. Re-point the app: new project = new URL + anon key → regenerate
   `lib/config/supabase_config.dart`, update GitHub secrets
   (`SUPABASE_URL`, `SUPABASE_ANON_KEY`), redeploy Edge Functions
   (`supabase functions deploy …`), reset Edge Function secrets
   (`ANTHROPIC_API_KEY`, `ALERT_WEBHOOK_URL`), update Supabase Auth URL
   allowlist (`https://tablelab.app/**`) and Google OAuth redirect.
6. Run `scripts/smoke-test.mjs` against the new project before announcing
   recovery.

Step 5 is the long pole — it's why the drill matters: the database restore
itself should be the easy 20 minutes.

## Drill log

| Date | Backup | Result | Notes |
|---|---|---|---|
| 2026-06-11 | 2026-06-11_0518 | ✅ PASSED | 12/12 counts matched (1546 sessions, 36 hands, 34 users, 13 policies); 134 grants restored. Backup taken via pooler (direct IPv6 timed out). |
