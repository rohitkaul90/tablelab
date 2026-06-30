<#
.SYNOPSIS
  One-command vCPU GTO-frequency-library solve. Launches an EC2 instance from the
  golden AMI (toolchain + built console_solver + deps already baked in -> no Phase-2
  build), syncs the current branch over the baked-in repo, and starts the solve in a
  detached tmux session. Optionally waits -> pulls the library back -> terminates.

  Operator-only. Pairs with tool/solver/VCPU_RUNBOOK.md (which this automates) and the
  golden AMI from that runbook. Needs the AWS CLI configured + the SSH key at
  ~/.ssh/<KeyName>.pem (default tablelab-solver). Run from the repo root.

  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads a no-BOM file as the
  system codepage, so a stray em-dash/ellipsis can decode into a Unicode quote and
  break parsing. Use '-' and '...' not the unicode glyphs.

.EXAMPLE
  # River re-trial: 6 spots, parallel 2. Read ~/solve.log (timing) + free -g (RAM)
  # over SSH; do NOT auto-pull a --limit run (it would pull a PARTIAL library).
  .\tool\solver\vcpu-solve.ps1 -GridArgs "--limit 6 --parallel 2"

.EXAMPLE
  # Full river solve: start + detach, manage the pull/terminate yourself.
  .\tool\solver\vcpu-solve.ps1 -GridArgs "--parallel 2"

.EXAMPLE
  # Full river solve, fire-and-forget: wait -> pull library -> terminate.
  .\tool\solver\vcpu-solve.ps1 -GridArgs "--parallel 2" -PullAndTerminate

.EXAMPLE
  # Deep-SPR turn re-solve on a bigger box (spot, more parallel).
  .\tool\solver\vcpu-solve.ps1 -Profile turn -InstanceType r7i.24xlarge -GridArgs "--parallel 8" -Spot
#>
param(
  [ValidateSet('turn', 'river')]
  [string]$Profile = 'river',
  # Extra args passed verbatim to freq_grid.dart (e.g. "--limit 6 --parallel 2").
  [string]$GridArgs = '--parallel 2',
  # Dart old-gen heap cap (MB). River REQUIRES a big heap or it OOMs parsing dumps.
  [int]$HeapMB = 200000,
  # Solver worker threads (8 is the stable max - 16 raced/crashed on wet trees).
  [int]$Threads = 8,
  # Per-spot solver wall cap (s).
  [int]$TimeoutS = 7200,
  [string]$InstanceType = 'r7i.8xlarge',
  # Fall back through these (same 256 GB class) if the chosen type lacks capacity.
  [string[]]$Fallbacks = @('r6i.8xlarge', 'r6a.8xlarge', 'r5.8xlarge'),
  # On-demand by default (spot kept getting reclaimed mid-setup). -Spot opts in.
  [switch]$Spot,
  [string]$Branch = 'feature/dce-river-cells',
  [string]$AmiId = 'ami-04c312a0a89b077c2',
  [string]$Region = 'us-east-2',
  [string]$KeyName = 'tablelab-solver',
  [string]$SgName = 'tablelab-solver-sg',
  # Wait for the solve to finish, then pull the library + cache and terminate.
  # FULL solves only - it refuses to auto-pull a --limit partial.
  [switch]$PullAndTerminate
)

$ErrorActionPreference = 'Stop'
$key = Join-Path $HOME ".ssh\$KeyName.pem"
if (-not (Test-Path $key)) { throw "SSH key not found: $key" }
$repo = & git rev-parse --show-toplevel 2>$null
if (-not $repo) { throw "Run this from inside the repo (git rev-parse failed)." }

function Invoke-Aws { # run aws, throw on non-zero exit (native exe - $ErrorAction won't)
  $out = aws @args
  if ($LASTEXITCODE -ne 0) { throw "aws $($args -join ' ') failed (exit $LASTEXITCODE)" }
  return $out
}

# -- 1. Security group + allow this IP ----------------------------------------
$sg = Invoke-Aws ec2 describe-security-groups --region $Region `
  --filters "Name=group-name,Values=$SgName" `
  --query 'SecurityGroups[0].GroupId' --output text
if (-not $sg -or $sg -eq 'None') { throw "Security group '$SgName' not found in $Region." }
$myip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
# Harmless 'InvalidPermission.Duplicate' if the rule already exists. Wrap it so the
# duplicate-path stderr can't surface as a terminating error under -EAP Stop and
# abort the launcher on its (very common) second run; reset $LASTEXITCODE after.
try {
  aws ec2 authorize-security-group-ingress --region $Region --group-id $sg `
    --protocol tcp --port 22 --cidr "$myip/32" 2>$null
} catch { }
$global:LASTEXITCODE = 0
Write-Host "SG $sg, SSH allowed from $myip"

# -- 2. Launch from the golden AMI (capacity fallback) ------------------------
$tag = 'ResourceType=instance,Tags=[{Key=Name,Value=tablelab-solver}]'
$iid = $null
foreach ($type in (@($InstanceType) + $Fallbacks)) {
  $a = @('ec2', 'run-instances', '--region', $Region, '--image-id', $AmiId,
    '--instance-type', $type, '--key-name', $KeyName, '--security-group-ids', $sg,
    '--tag-specifications', $tag, '--count', '1',
    '--query', 'Instances[0].InstanceId', '--output', 'text')
  if ($Spot) { $a += @('--instance-market-options', 'MarketType=spot') }
  Write-Host "Launching $type ($(if ($Spot) {'spot'} else {'on-demand'}))..."
  $out = aws @a
  # Pull the i-... id out of stdout robustly - an AWS CLI notice line alongside the
  # queried InstanceId must NOT make a real launch look like a capacity failure
  # (which would launch a fallback and orphan this running instance).
  $newId = $null
  if ($LASTEXITCODE -eq 0) {
    $newId = ("$out" -split "`r?`n" | ForEach-Object { $_.Trim() } |
      Where-Object { $_ -match '^i-[0-9a-f]+$' } | Select-Object -First 1)
  }
  if ($newId) { $iid = $newId; $itype = $type; break }
  Write-Host "  $type unavailable - trying next"
}
if (-not $iid) { throw "No capacity on any of: $InstanceType $($Fallbacks -join ' ')" }
Write-Host "Instance $iid ($itype) launching; waiting for running..."
Invoke-Aws ec2 wait instance-running --region $Region --instance-ids $iid | Out-Null
$pubip = (Invoke-Aws ec2 describe-instances --region $Region --instance-ids $iid `
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text).Trim()
Write-Host "PUBIP=$pubip"

# -- 3. Wait for SSH, clear any reused-IP host key ----------------------------
ssh-keygen -R $pubip *> $null
$ssh = @('-i', $key, '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10', "ubuntu@$pubip")
Write-Host "Waiting for SSH..."
$sshOk = $false
foreach ($i in 1..30) {
  ssh @ssh 'echo ready' *> $null
  if ($LASTEXITCODE -eq 0) { $sshOk = $true; break }
  Start-Sleep 10
}
if (-not $sshOk) { throw "SSH never came up on $pubip - instance $iid left running for triage." }

# -- 4. Sync the branch over the baked-in repo, refresh deps ------------------
Write-Host "Syncing branch '$Branch' -> box..."
$tgz = Join-Path $env:TEMP 'vcpu-repo.tgz'
Push-Location $repo
try { & git archive --format=tar.gz -o $tgz $Branch; if ($LASTEXITCODE -ne 0) { throw "git archive $Branch failed" } }
finally { Pop-Location }
scp -i $key $tgz "ubuntu@${pubip}:~/repo.tgz"
if ($LASTEXITCODE -ne 0) { throw "scp repo.tgz failed" }
ssh @ssh 'mkdir -p ~/poker_tracker && tar -xzf ~/repo.tgz -C ~/poker_tracker && cd ~/poker_tracker && flutter pub get'
if ($LASTEXITCODE -ne 0) { throw "remote extract / flutter pub get failed" }

# -- 5. Start the solve in a detached tmux session ----------------------------
# Build a run-solve.sh locally (LF endings) and scp it, to avoid nested PS->ssh->bash
# quoting. `$HOME is escaped so it stays literal for the remote shell; $Profile etc.
# are interpolated by PowerShell.
$solveSh = @"
#!/usr/bin/env bash
cd ~/poker_tracker
export TEXASSOLVER_DIR=`$HOME/texassolver-source
export TEXASSOLVER_BIN=`$HOME/texassolver-source/build/console_solver
export TMPDIR=/mnt/scratch
TLSOLVE_PROFILE=$Profile TLSOLVE_ACCURACY=0.5 TLSOLVE_TIMEOUT_S=$TimeoutS TLSOLVE_MAXITER=400 TLSOLVE_THREADS=$Threads dart --old_gen_heap_size=$HeapMB run tool/solver/freq_grid.dart $GridArgs 2>&1 | tee ~/solve.log
"@
$localSh = Join-Path $env:TEMP 'run-solve.sh'
[IO.File]::WriteAllText($localSh, ($solveSh -replace "`r`n", "`n"))
scp -i $key $localSh "ubuntu@${pubip}:~/run-solve.sh"
if ($LASTEXITCODE -ne 0) { throw "scp run-solve.sh failed" }
ssh @ssh 'tmux kill-session -t solve 2>/dev/null; tmux new -d -s solve "bash ~/run-solve.sh"'
if ($LASTEXITCODE -ne 0) { throw "failed to start the tmux solve session" }
Write-Host ""
Write-Host "Solve started on $iid ($itype): TLSOLVE_PROFILE=$Profile $GridArgs"
Write-Host ""
Write-Host "  Watch:      ssh -i `"$key`" ubuntu@$pubip   then  tmux attach -t solve"
Write-Host "  Tail log:   ssh -i `"$key`" ubuntu@$pubip 'tail -f ~/solve.log'"
Write-Host "  RAM:        ssh -i `"$key`" ubuntu@$pubip 'watch -n15 free -g'"
Write-Host "  Pull lib:   scp -i `"$key`" ubuntu@${pubip}:~/poker_tracker/assets/gto_freq_library.json ./assets/"
Write-Host "  Terminate:  aws ec2 terminate-instances --region $Region --instance-ids $iid"
Write-Host ""

# -- 6. Optional: wait for completion, pull library + cache, terminate --------
if ($PullAndTerminate) {
  if ($GridArgs -match '--limit') {
    Write-Warning "GridArgs has --limit: this is a PARTIAL solve. Pulling its library would"
    Write-Warning "clobber the committed one. Skipping auto-pull; leaving the box running."
    Write-Warning "Inspect over SSH, then terminate manually with the command above."
    return
  }
  Write-Host "Waiting for the solve to finish..."
  # Poll three states: 'wrote' = freq_grid printed 'Wrote ...' AFTER writing the
  # library (the only safe sentinel - 'Grid: solved' prints BEFORE the file write,
  # and isn't printed at all if every spot failed); 'dead' = the tmux solve session
  # ended WITHOUT writing (crash / OOM-kill / all-failed / _writeLibrary aborted on
  # a guard) - must NOT pull (stale lib) or terminate; 'running' = keep waiting.
  # Check 'wrote' BEFORE 'dead' so a clean finish (session ends right after writing)
  # still reads as success.
  do {
    Start-Sleep 30
    $state = (ssh @ssh "if grep -q '^Wrote ' ~/solve.log 2>/dev/null; then echo wrote; elif tmux has-session -t solve 2>/dev/null; then echo running; else echo dead; fi")
    $state = "$state".Trim()
  } while ($state -eq 'running')

  if ($state -ne 'wrote') {
    ssh @ssh "tail -n 30 ~/solve.log"
    Write-Warning "Solve ended WITHOUT writing the library (crash / OOM / all spots failed /"
    Write-Warning "a _writeLibrary guard aborted). Instance $iid is LEFT RUNNING for triage -"
    Write-Warning "do NOT trust a pulled library. Inspect above, then terminate when done:"
    Write-Warning "  aws ec2 terminate-instances --region $Region --instance-ids $iid"
    return
  }

  ssh @ssh "tail -n 3 ~/solve.log"
  Write-Host "Pulling library + cache back..."
  # Relative dest paths from the repo root (Push-Location) - a 'C:/...' absolute path
  # can trip scp's host:path colon parsing on some builds. Guard BOTH pulls: only
  # terminate if both succeeded, else leave the box up so the solve output (and the
  # resumable freq_grid_results.json) isn't destroyed.
  Push-Location $repo
  try {
    scp -i $key "ubuntu@${pubip}:~/poker_tracker/assets/gto_freq_library.json" 'assets/gto_freq_library.json'
    $okLib = ($LASTEXITCODE -eq 0)
    scp -i $key "ubuntu@${pubip}:~/poker_tracker/tool/solver/freq_grid_results.json" 'tool/solver/freq_grid_results.json'
    $okCache = ($LASTEXITCODE -eq 0)
  } finally { Pop-Location }
  if (-not ($okLib -and $okCache)) {
    Write-Warning "A pull FAILED (library=$okLib cache=$okCache). Instance $iid LEFT RUNNING so"
    Write-Warning "the solve output isn't lost - retry the scp, then terminate manually:"
    Write-Warning "  aws ec2 terminate-instances --region $Region --instance-ids $iid"
    return
  }
  Write-Host "Terminating $iid..."
  Invoke-Aws ec2 terminate-instances --region $Region --instance-ids $iid | Out-Null
  Write-Host "Done. Library pulled (review 'git diff', then 'git add -f' it) + instance terminated."
}
