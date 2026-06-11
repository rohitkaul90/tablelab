# TableLab restore drill: load a db-backup.ps1 backup into a throwaway local
# Postgres cluster and verify it matches the prod manifest.
# Docs: scripts/DB_BACKUP_RESTORE.md
#
# Uses initdb to build a scratch cluster on -Port (default 5433) so it never
# touches the installed postgresql-x64-17 service. The cluster is deleted at
# the end unless -KeepCluster is passed.

param(
    # Backup folder to restore; defaults to the newest under %USERPROFILE%\TableLabBackups
    [string]$BackupDir = "",
    [int]$Port = 5433,
    [switch]$KeepCluster
)

$ErrorActionPreference = "Stop"
$pgbin = "C:\Program Files\PostgreSQL\17\bin"

if ($BackupDir -eq "") {
    $latest = Get-ChildItem "$env:USERPROFILE\TableLabBackups" -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $latest) { Write-Error "No backups found. Run scripts\db-backup.ps1 first." }
    $BackupDir = $latest.FullName
}
Write-Host "Restoring backup: $BackupDir"
foreach ($f in @("schema-public.sql", "auth-schema-drill-only.sql", "data.sql", "row-counts.txt")) {
    if (-not (Test-Path "$BackupDir\$f")) { Write-Error "Missing $f in $BackupDir" }
}

$scratch = Join-Path $env:TEMP ("tablelab-drill-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$dataDir = "$scratch\pgdata"
New-Item -ItemType Directory -Force $scratch | Out-Null
$local = @("--host", "localhost", "--port", "$Port", "--username", "postgres", "--no-password")
$started = $false

try {
    Write-Host "Creating scratch cluster..."
    & "$pgbin\initdb.exe" -D $dataDir -U postgres -A trust -E UTF8 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "initdb failed" }

    # Start postgres directly via Start-Process with file-redirected output.
    # Do NOT pipe `pg_ctl start` — the spawned daemon inherits the pipe handle
    # and the pipeline never completes, hanging the script (bit us 2026-06-11).
    $pgProc = Start-Process "$pgbin\postgres.exe" -ArgumentList "-D", "`"$dataDir`"", "-p", "$Port" `
        -RedirectStandardError "$scratch\pg.log" -RedirectStandardOutput "$scratch\pg.out.log" `
        -NoNewWindow -PassThru
    $ready = $false
    foreach ($i in 1..30) {
        Start-Sleep -Seconds 1
        & "$pgbin\pg_isready.exe" -h localhost -p $Port --quiet
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        if ($pgProc.HasExited) { break }
    }
    if (-not $ready) { throw "postgres failed to start - see $scratch\pg.log" }
    $started = $true

    Write-Host "Creating Supabase roles, extensions, drill database..."
    $prelude = @"
do `$`$ begin
  begin create role anon nologin; exception when duplicate_object then null; end;
  begin create role authenticated nologin; exception when duplicate_object then null; end;
  begin create role service_role nologin bypassrls; exception when duplicate_object then null; end;
  begin create role supabase_auth_admin nologin; exception when duplicate_object then null; end;
  begin create role supabase_admin nologin; exception when duplicate_object then null; end;
  begin create role dashboard_user nologin; exception when duplicate_object then null; end;
end `$`$;
"@
    $prelude | & "$pgbin\psql.exe" @local -d postgres -v ON_ERROR_STOP=1 -f -
    if ($LASTEXITCODE -ne 0) { throw "role prelude failed" }
    & "$pgbin\psql.exe" @local -d postgres -v ON_ERROR_STOP=1 -c "create database tablelab_drill"
    if ($LASTEXITCODE -ne 0) { throw "create database failed" }
    # Piped via stdin: embedded double quotes in -c args get mangled by
    # PowerShell 5.1 native-command argument parsing.
    $extSql = @"
-- the dump recreates schema public itself (with its grants); drop the default one
drop schema if exists public cascade;
create schema if not exists extensions;
create extension if not exists pgcrypto schema extensions;
create extension if not exists "uuid-ossp" schema extensions;
alter database tablelab_drill set search_path to "`$user", public, extensions;
"@
    $extSql | & "$pgbin\psql.exe" @local -d tablelab_drill -v ON_ERROR_STOP=1 -f -
    if ($LASTEXITCODE -ne 0) { throw "extensions setup failed" }

    # auth scaffold: Supabase-managed schema, only needed so public FKs/policies
    # and auth data have something to land on. Errors here are tolerated (e.g.
    # the on_auth_user_created trigger references public.handle_new_user(),
    # which only exists after schema-public.sql — harmless for a drill).
    # EAP must be Continue around this call: under Stop, PS 5.1 turns native
    # stderr into a terminating NativeCommandError when redirected.
    Write-Host "Applying auth schema scaffold (errors tolerated, logged)..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & "$pgbin\psql.exe" @local -d tablelab_drill -f "$BackupDir\auth-schema-drill-only.sql" > "$scratch\auth-schema.log" 2>&1
    $ErrorActionPreference = $prevEAP

    # The dump we actually care about: must apply cleanly.
    Write-Host "Applying public schema (strict)..."
    & "$pgbin\psql.exe" @local -d tablelab_drill -v ON_ERROR_STOP=1 -f "$BackupDir\schema-public.sql"
    if ($LASTEXITCODE -ne 0) { throw "PUBLIC SCHEMA RESTORE FAILED - the backup is not cleanly restorable" }

    # session_replication_role=replica disables FK triggers so data-only load
    # order can't fail; superuser-only, which we are on the scratch cluster.
    Write-Host "Loading data (strict)..."
    & "$pgbin\psql.exe" @local -d tablelab_drill -v ON_ERROR_STOP=1 `
        -c "set session_replication_role = replica" -f "$BackupDir\data.sql"
    if ($LASTEXITCODE -ne 0) { throw "DATA RESTORE FAILED - the backup is not cleanly restorable" }

    Write-Host ""
    Write-Host "=== VERIFICATION (local vs prod manifest) ==="
    $fail = 0
    foreach ($line in Get-Content "$BackupDir\row-counts.txt") {
        if ($line.Trim() -eq "") { continue }
        $parts = $line -split "`t"
        $name = $parts[0]; $expected = $parts[1]
        if ($name -eq "pg_policies") {
            $actual = (& "$pgbin\psql.exe" @local -d tablelab_drill --no-align --tuples-only -c "select count(*) from pg_policies where schemaname='public'").Trim()
        } else {
            $actual = (& "$pgbin\psql.exe" @local -d tablelab_drill --no-align --tuples-only -c "select count(*) from $name").Trim()
        }
        if ($actual -eq $expected) {
            Write-Host ("  OK    {0}  ({1})" -f $name, $actual)
        } else {
            Write-Host ("  FAIL  {0}  expected {1}, got {2}" -f $name, $expected, $actual)
            $fail++
        }
    }
    $grants = (& "$pgbin\psql.exe" @local -d tablelab_drill --no-align --tuples-only -c "select count(*) from information_schema.role_table_grants where table_schema='public' and grantee in ('anon','authenticated','service_role')").Trim()
    Write-Host "  INFO  grants to anon/authenticated/service_role on public tables: $grants"

    Write-Host ""
    if ($fail -eq 0) {
        Write-Host "DRILL PASSED - backup is restorable and complete." -ForegroundColor Green
    } else {
        Write-Host "DRILL FAILED - $fail mismatched counts. Investigate before trusting this backup." -ForegroundColor Red
    }
} finally {
    if ($started -and -not $KeepCluster) {
        & "$pgbin\pg_ctl.exe" -D $dataDir -m fast -w stop | Out-Null
        Remove-Item -Recurse -Force $scratch
        Write-Host "Scratch cluster removed."
    } elseif ($started) {
        Write-Host "Cluster kept: psql -h localhost -p $Port -U postgres -d tablelab_drill  (data dir: $dataDir)"
    }
}
