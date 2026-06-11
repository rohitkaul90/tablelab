# TableLab prod database backup (schema + data + verification manifest).
# Docs: scripts/DB_BACKUP_RESTORE.md
#
# Credentials: reads the database password from launch/db-password.txt
# (gitignored) or $env:SUPABASE_DB_PASSWORD. Never pass it on the command line.
#
# Output (default %USERPROFILE%\TableLabBackups\<timestamp>\ — OUTSIDE the repo;
# dumps contain user emails and must never be committed):
#   schema-public.sql           public schema DDL incl. RLS policies + GRANTs
#   auth-schema-drill-only.sql  auth schema DDL, stripped of owners/privileges.
#                               ONLY for local restore drills — never apply to a
#                               real Supabase project (auth is Supabase-managed).
#   data.sql                    data for public + auth schemas
#   row-counts.txt              prod row counts + policy count, used by
#                               db-restore-verify.ps1 to validate the restore

param(
    # Set if direct IPv6 connection fails: the "Session pooler" host from
    # Supabase dashboard -> Connect (e.g. aws-0-us-west-1.pooler.supabase.com)
    [string]$PoolerHost = "",
    [string]$OutRoot = "$env:USERPROFILE\TableLabBackups"
)

$ErrorActionPreference = "Stop"
$pgbin = "C:\Program Files\PostgreSQL\17\bin"
$repoRoot = Split-Path -Parent $PSScriptRoot

$ref = (Get-Content "$repoRoot\supabase\.temp\project-ref" -ErrorAction Stop).Trim()

# --- credentials ---
$pwFile = "$repoRoot\launch\db-password.txt"
if (Test-Path $pwFile) {
    $pw = (Get-Content $pwFile -Raw).Trim()
} elseif ($env:SUPABASE_DB_PASSWORD) {
    $pw = $env:SUPABASE_DB_PASSWORD
} else {
    Write-Error "No DB password. Put it in launch\db-password.txt (gitignored) or set SUPABASE_DB_PASSWORD. Find/reset it: Supabase dashboard -> Project Settings -> Database."
}

# --- connection (direct is IPv6-only; pooler is the IPv4 fallback) ---
if ($PoolerHost -ne "") {
    $dbHost = $PoolerHost
    $dbUser = "postgres.$ref"
} else {
    $dbHost = "db.$ref.supabase.co"
    $dbUser = "postgres"
}
$common = @("--host", $dbHost, "--port", "5432", "--username", $dbUser, "--dbname", "postgres", "--no-password")

$stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$outDir = Join-Path $OutRoot $stamp
New-Item -ItemType Directory -Force $outDir | Out-Null

$env:PGPASSWORD = $pw
try {
    Write-Host "Dumping public schema DDL (policies + grants)..."
    & "$pgbin\pg_dump.exe" @common --schema-only --schema=public -f "$outDir\schema-public.sql"
    if ($LASTEXITCODE -ne 0) { throw "schema dump failed ($LASTEXITCODE)" }

    Write-Host "Dumping auth schema DDL (drill scaffold only)..."
    & "$pgbin\pg_dump.exe" @common --schema-only --schema=auth --no-owner --no-privileges -f "$outDir\auth-schema-drill-only.sql"
    if ($LASTEXITCODE -ne 0) { throw "auth schema dump failed ($LASTEXITCODE)" }

    Write-Host "Dumping data (public + auth)..."
    & "$pgbin\pg_dump.exe" @common --data-only --schema=public --schema=auth -f "$outDir\data.sql"
    if ($LASTEXITCODE -ne 0) { throw "data dump failed ($LASTEXITCODE)" }

    Write-Host "Writing verification manifest..."
    $tables = & "$pgbin\psql.exe" @common --no-align --tuples-only -c "select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE' order by 1"
    if ($LASTEXITCODE -ne 0) { throw "table list query failed ($LASTEXITCODE)" }
    $lines = @()
    foreach ($t in $tables) {
        if ($t.Trim() -eq "") { continue }
        $n = (& "$pgbin\psql.exe" @common --no-align --tuples-only -c "select count(*) from public.""$($t.Trim())""").Trim()
        $lines += "public.$($t.Trim())`t$n"
    }
    $n = (& "$pgbin\psql.exe" @common --no-align --tuples-only -c "select count(*) from auth.users").Trim()
    $lines += "auth.users`t$n"
    $n = (& "$pgbin\psql.exe" @common --no-align --tuples-only -c "select count(*) from pg_policies where schemaname='public'").Trim()
    $lines += "pg_policies`t$n"
    $lines | Out-File "$outDir\row-counts.txt" -Encoding utf8
} finally {
    $env:PGPASSWORD = $null
}

Write-Host ""
Write-Host "Backup complete: $outDir"
Get-ChildItem $outDir | Select-Object Name, @{n="KB";e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize
Write-Host "Manifest:"
Get-Content "$outDir\row-counts.txt"
