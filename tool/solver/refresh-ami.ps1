<#
.SYNOPSIS
  Golden-AMI refresh for the TLSD binary-dump solver (full-density plan, WS1c
  cloud step). Launches a 256 GB box from the CURRENT golden AMI, syncs the
  patched TexasSolver source (from its local-only git repo) + the current repo
  branch, rebuilds console_solver on Linux, then gates the bake behind two
  validations:
    1. SMOKE  - tiny dual-dump solve -> validate_dump equivalence (seconds)
    2. DEEP   - a REAL srp_late deep spot (SPR 15, river profile) solved once
                with TLSOLVE_DUMP_FMT=both -> JSON vs TLSD cells equivalence.
                This is the ~15 GB-dump / ~150 GB-JSON-heap class the whole
                TLSD project exists for (~60-90 min on 32 vCPU).
  Only if the gates pass does it create-image the new golden AMI, wait for it,
  and terminate the box. On ANY failure the box is LEFT RUNNING for triage.

  Cost: r7a.8xlarge on-demand ~2.5 USD/hr x ~2-2.5 h ~= 6 USD.

  AFTER a successful run (manual, deliberate):
    1. Update -AmiId defaults (vcpu-solve.ps1 + this file) to the NEW AMI id.
    2. Flip TLSOLVE_DUMP_FMT default 'json' -> 'bin' in run_solver.dart
       (the WS1c gate is now passed) + update VCPU_RUNBOOK.md / CLAUDE.md.
    3. KEEP the old AMI until the first successful solve off the new one, then
       deregister it + delete its snapshot.

  NOTE: keep this file ASCII-only (PS 5.1 codepage pitfall - see vcpu-solve.ps1).

.EXAMPLE
  # Full refresh incl. the deep gate (recommended; ~2-2.5 h):
  .\tool\solver\refresh-ami.ps1

.EXAMPLE
  # Rebuild + smoke only (e.g. iterating on a build break; NOT enough to flip
  # the TLSD default - the deep gate is the point):
  .\tool\solver\refresh-ami.ps1 -SkipDeepValidate -KeepBox
#>
param(
  # Current golden AMI to refresh FROM (us-east-2).
  [string]$AmiId = 'ami-04c312a0a89b077c2',
  [string]$Region = 'us-east-2',
  # 256 GB class: enough for one deep solve (~89 GB) and the deep JSON-side
  # tabulate (~150 GB heap) run SEQUENTIALLY by validate_dump.
  [string]$InstanceType = 'r7a.8xlarge',
  [string[]]$Fallbacks = @('r7i.8xlarge', 'r6i.8xlarge', 'r6a.8xlarge'),
  [string]$KeyName = 'tablelab-solver',
  [string]$SgName = 'tablelab-solver-sg',
  # Repo branch to sync (empty = current). The Dart side of TLSD lives on the
  # branch, so the box must run the same branch you validated locally.
  [string]$Branch = '',
  # The licensed TexasSolver source dir (a LOCAL-ONLY git repo since 2026-07-09
  # - never pushed). Default: read from tool/solver/solver_config.json.
  [string]$SolverSourceDir = '',
  # Name for the new AMI (must be unique per account+region).
  [string]$NewAmiName = ('tablelab-solver-tlsd-' + (Get-Date -Format 'yyyyMMdd-HHmm')),
  # Skip the ~60-90 min deep gate (build+smoke only). The refresh then does NOT
  # qualify as the WS1c deep validation - don't flip the TLSD default off it.
  [switch]$SkipDeepValidate,
  # Leave the box running after the bake (or after a -SkipDeepValidate pass).
  [switch]$KeepBox
)

$ErrorActionPreference = 'Stop'
$key = Join-Path $HOME ".ssh\$KeyName.pem"
if (-not (Test-Path $key)) { throw "SSH key not found: $key" }
$repo = & git rev-parse --show-toplevel 2>$null
if (-not $repo) { throw "Run this from inside the repo (git rev-parse failed)." }
if (-not $Branch) {
  $Branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  if (-not $Branch -or $Branch -eq 'HEAD') { throw "Cannot resolve current branch - pass -Branch." }
}
if (-not $SolverSourceDir) {
  $cfgPath = Join-Path $repo 'tool\solver\solver_config.json'
  if (-not (Test-Path $cfgPath)) { throw "No -SolverSourceDir and no solver_config.json." }
  $SolverSourceDir = (Get-Content $cfgPath -Raw | ConvertFrom-Json).sourceDir
}
if (-not (Test-Path (Join-Path $SolverSourceDir '.git'))) {
  throw "Solver source at $SolverSourceDir is not a git repo - the sync uses git archive (vsbuild/ etc. are gitignored). Init it first (see tool/solver/README.md patch #4)."
}

function Invoke-Aws {
  $out = aws @args
  if ($LASTEXITCODE -ne 0) { throw "aws $($args -join ' ') failed (exit $LASTEXITCODE)" }
  return $out
}

# -- 1. Security group + this IP ----------------------------------------------
$sg = Invoke-Aws ec2 describe-security-groups --region $Region `
  --filters "Name=group-name,Values=$SgName" `
  --query 'SecurityGroups[0].GroupId' --output text
if (-not $sg -or $sg -eq 'None') { throw "Security group '$SgName' not found in $Region." }
$myip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
try {
  aws ec2 authorize-security-group-ingress --region $Region --group-id $sg `
    --protocol tcp --port 22 --cidr "$myip/32" 2>$null
} catch { }
$global:LASTEXITCODE = 0
Write-Host "SG $sg, SSH allowed from $myip"

# -- 2. Launch (on-demand - a reclaim mid-bake would waste the whole run) -----
$tag = 'ResourceType=instance,Tags=[{Key=Name,Value=tablelab-ami-refresh}]'
$iid = $null
foreach ($type in (@($InstanceType) + $Fallbacks)) {
  Write-Host "Launching $type (on-demand)..."
  $out = aws ec2 run-instances --region $Region --image-id $AmiId `
    --instance-type $type --key-name $KeyName --security-group-ids $sg `
    --tag-specifications $tag --count 1 `
    --query 'Instances[0].InstanceId' --output text
  $newId = $null
  if ($LASTEXITCODE -eq 0) {
    $newId = ("$out" -split "`r?`n" | ForEach-Object { $_.Trim() } |
      Where-Object { $_ -match '^i-[0-9a-f]+$' } | Select-Object -First 1)
  }
  if ($newId) { $iid = $newId; $itype = $type; break }
  Write-Host "  $type unavailable - trying next"
}
if (-not $iid) { throw "No capacity on any of: $InstanceType $($Fallbacks -join ' ')" }
Write-Host "Instance $iid ($itype); waiting for running..."
Invoke-Aws ec2 wait instance-running --region $Region --instance-ids $iid | Out-Null
$pubip = (Invoke-Aws ec2 describe-instances --region $Region --instance-ids $iid `
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text).Trim()
Write-Host "PUBIP=$pubip"

# -- 3. SSH (timed-job hardened - see vcpu-solve.ps1 for the war stories) -----
try { ssh-keygen -R $pubip *> $null } catch { }
$global:LASTEXITCODE = 0
$ssh = @('-i', $key, '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10', '-o', 'BatchMode=yes', '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=2', "ubuntu@$pubip")

function Invoke-SshTimed {
  param([string]$RemoteCmd, [int]$TimeoutSec = 30)
  $j = Start-Job -ScriptBlock {
    param($sshArgs, $cmd)
    $out = ssh @sshArgs $cmd 2>$null
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
  } -ArgumentList (, $ssh), $RemoteCmd
  if (Wait-Job $j -Timeout $TimeoutSec) {
    $r = Receive-Job $j | Select-Object -Last 1
    Remove-Job $j -Force
    return $r
  }
  Stop-Job $j
  Remove-Job $j -Force
  return $null
}

Write-Host "Waiting for SSH..."
$sshOk = $false
foreach ($i in 1..30) {
  $r = Invoke-SshTimed 'echo ready' -TimeoutSec 20
  if ($r -and $r.Code -eq 0) { $sshOk = $true; break }
  Start-Sleep 10
}
if (-not $sshOk) { throw "SSH never came up on $pubip - instance $iid left running for triage." }

# -- 4. Sync patched solver source + repo branch ------------------------------
Write-Host "Syncing patched solver source (git archive from $SolverSourceDir)..."
$srcTgz = Join-Path $env:TEMP 'tlsd-solver-src.tgz'
Push-Location $SolverSourceDir
try { & git archive --format=tar.gz -o $srcTgz HEAD; if ($LASTEXITCODE -ne 0) { throw "git archive (solver source) failed" } }
finally { Pop-Location }
scp -i $key $srcTgz "ubuntu@${pubip}:~/solver-src.tgz"
if ($LASTEXITCODE -ne 0) { throw "scp solver-src.tgz failed" }
# Extract OVER the baked source: same delivery baseline + patches, so tracked
# files overwrite cleanly; the stale Linux build/ is removed by the rebuild.
ssh @ssh 'mkdir -p ~/texassolver-source && tar -xzf ~/solver-src.tgz -C ~/texassolver-source'
if ($LASTEXITCODE -ne 0) { throw "remote solver-source extract failed" }

Write-Host "Syncing repo branch '$Branch'..."
$repoTgz = Join-Path $env:TEMP 'tlsd-repo.tgz'
Push-Location $repo
try { & git archive --format=tar.gz -o $repoTgz $Branch; if ($LASTEXITCODE -ne 0) { throw "git archive $Branch failed" } }
finally { Pop-Location }
scp -i $key $repoTgz "ubuntu@${pubip}:~/repo.tgz"
if ($LASTEXITCODE -ne 0) { throw "scp repo.tgz failed" }
ssh @ssh 'mkdir -p ~/poker_tracker && tar -xzf ~/repo.tgz -C ~/poker_tracker && cd ~/poker_tracker && flutter pub get'
if ($LASTEXITCODE -ne 0) { throw "remote extract / flutter pub get failed" }

# -- 5. Box-side build + validation script (sentinel-driven) ------------------
$deepFlag = if ($SkipDeepValidate) { '0' } else { '1' }
$validateSh = @"
#!/usr/bin/env bash
set -o pipefail
{
echo '=== stage: build ==='
cd ~/texassolver-source
rm -rf build && mkdir -p build && cd build
if cmake .. -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release && make -j`$(nproc) console_solver; then
  echo 'BUILD OK'
else
  echo 'REFRESH FAILED (build)'; exit 1
fi
if strings ~/texassolver-source/build/console_solver | grep -q dump_result_bin; then
  echo 'PATCH PRESENT'
else
  echo 'REFRESH FAILED (dump_result_bin missing from binary - wrong source synced?)'; exit 1
fi

echo '=== stage: smoke ==='
cd ~/poker_tracker
export TEXASSOLVER_DIR=`$HOME/texassolver-source
export TEXASSOLVER_BIN=`$HOME/texassolver-source/build/console_solver
export TMPDIR=/dev/shm
sudo sysctl -w vm.max_map_count=2000000 >/dev/null 2>&1 || true
rm -rf /dev/shm/tlsolve_* /dev/shm/tlsd_smoke 2>/dev/null || true
mkdir -p /dev/shm/tlsd_smoke
cat > /dev/shm/tlsd_smoke/input.txt <<'EOF'
set_pot 10
set_effective_stack 20
set_board Ks,9h,4c
set_range_ip AA,KK,QQ,AKs,AQs,KQs,AKo
set_range_oop 99,88,77,A9s,K9s,QTs,JTs,T9s,98s
set_bet_sizes ip,flop,bet,50
set_bet_sizes ip,flop,allin
set_bet_sizes oop,flop,bet,50
set_bet_sizes oop,flop,allin
set_bet_sizes ip,turn,bet,66
set_bet_sizes ip,turn,allin
set_bet_sizes oop,turn,bet,66
set_bet_sizes oop,turn,allin
set_bet_sizes ip,river,bet,66
set_bet_sizes ip,river,allin
set_bet_sizes oop,river,bet,66
set_bet_sizes oop,river,allin
set_allin_threshold 0.67
build_tree
set_thread_num 4
set_accuracy 2.0
set_max_iteration 40
set_print_interval 10
set_use_isomorphism 1
start_solve
set_dump_rounds 2
dump_result /dev/shm/tlsd_smoke/dump.json
dump_result_bin /dev/shm/tlsd_smoke/dump.tlsd
EOF
if (cd ~/texassolver-source && ./build/console_solver -i /dev/shm/tlsd_smoke/input.txt >/dev/shm/tlsd_smoke/solve.out 2>&1) \
   && dart run tool/solver/validate_dump.dart /dev/shm/tlsd_smoke/dump.json /dev/shm/tlsd_smoke/dump.tlsd Ks9h4c 10 20 4; then
  echo 'SMOKE OK'
else
  tail -n 20 /dev/shm/tlsd_smoke/solve.out 2>/dev/null
  echo 'REFRESH FAILED (smoke)'; exit 1
fi
rm -rf /dev/shm/tlsd_smoke

echo '=== stage: deep ==='
if [ "$deepFlag" = "1" ]; then
  # One REAL srp_late deep spot (SPR 15, river profile), solved ONCE emitting
  # both dumps, both tabulated + compared in-process. The JSON side needs the
  # giant heap (~150 GB) - exactly the cost class TLSD removes; the box has
  # 256 GB and the phases run sequentially.
  if TLSOLVE_SCENARIO=srp_late_v_bb TLSOLVE_DUMP_FMT=both TLSOLVE_PROFILE=river \
     TLSOLVE_ACCURACY=0.5 TLSOLVE_MAXITER=400 TLSOLVE_THREADS=8 TLSOLVE_TIMEOUT_S=7200 \
     dart --old_gen_heap_size=170000 run tool/solver/validate_dump.dart --solve 'Ks 9h 4c' deep; then
    echo 'DEEP OK'
  else
    echo 'REFRESH FAILED (deep)'; exit 1
  fi
else
  echo 'DEEP SKIPPED'
fi
rm -f ~/solver-src.tgz ~/repo.tgz
echo 'REFRESH VALIDATION DONE'
} 2>&1 | tee ~/ami-validate.log
"@
$localSh = Join-Path $env:TEMP 'ami-refresh.sh'
[IO.File]::WriteAllText($localSh, ($validateSh -replace "`r`n", "`n"))
scp -i $key $localSh "ubuntu@${pubip}:~/ami-refresh.sh"
if ($LASTEXITCODE -ne 0) { throw "scp ami-refresh.sh failed" }
ssh @ssh 'tmux kill-session -t amiref 2>/dev/null; tmux new -d -s amiref "bash ~/ami-refresh.sh"'
if ($LASTEXITCODE -ne 0) { throw "failed to start the tmux validation session" }
Write-Host ""
Write-Host "Build + validation started ($(if ($SkipDeepValidate) {'smoke only'} else {'smoke + DEEP gate, ~60-90 min'}))."
Write-Host "  Watch:    ssh -i `"$key`" ubuntu@$pubip 'tail -f ~/ami-validate.log'"
Write-Host ""

# -- 6. Poll for the sentinel --------------------------------------------------
$failures = 0
do {
  Start-Sleep 60
  $r = Invoke-SshTimed "if grep -q 'REFRESH VALIDATION DONE' ~/ami-validate.log 2>/dev/null; then echo done; elif grep -q 'REFRESH FAILED' ~/ami-validate.log 2>/dev/null; then echo failed; elif tmux has-session -t amiref 2>/dev/null; then echo running; else echo dead; fi"
  if ($r -and $r.Code -eq 0 -and "$($r.Out)".Trim()) {
    $failures = 0
    $state = "$($r.Out)".Trim()
  } else {
    $failures++
    $state = 'running'
    if ($failures -ge 12) { $state = 'unreachable' }
  }
} while ($state -eq 'running')

if ($state -ne 'done') {
  $r = Invoke-SshTimed "tail -n 40 ~/ami-validate.log" -TimeoutSec 60
  if ($r) { Write-Host $r.Out }
  Write-Warning "Validation state '$state' - NOT baking an AMI. Instance $iid LEFT RUNNING"
  Write-Warning "for triage (~/ami-validate.log). Terminate when done:"
  Write-Warning "  aws ec2 terminate-instances --region $Region --instance-ids $iid"
  return
}
$r = Invoke-SshTimed "grep -E 'BUILD OK|PATCH PRESENT|SMOKE OK|DEEP OK|DEEP SKIPPED|mismatches' ~/ami-validate.log" -TimeoutSec 60
if ($r) { Write-Host $r.Out }

# -- 7. Bake the new golden AMI -------------------------------------------------
Write-Host "Creating AMI '$NewAmiName' from $iid (instance reboots)..."
$newAmi = (Invoke-Aws ec2 create-image --region $Region --instance-id $iid `
    --name $NewAmiName --description "TableLab solver golden AMI + TLSD binary dump (validated $(Get-Date -Format s))" `
    --query 'ImageId' --output text).Trim()
if ($newAmi -notmatch '^ami-') { throw "create-image returned '$newAmi'" }
Write-Host "New AMI: $newAmi - waiting for 'available' (a ~193 GB snapshot takes 10-30 min)..."
$deadline = (Get-Date).AddMinutes(45)
do {
  Start-Sleep 60
  $imgState = (aws ec2 describe-images --region $Region --image-ids $newAmi `
      --query 'Images[0].State' --output text 2>$null)
  Write-Host "  AMI state: $imgState"
} while ($imgState -ne 'available' -and (Get-Date) -lt $deadline)
if ($imgState -ne 'available') {
  Write-Warning "AMI $newAmi still '$imgState' after 45 min - check the console. Instance"
  Write-Warning "$iid LEFT RUNNING until the AMI is confirmed. Terminate manually after."
  return
}

if ($KeepBox) {
  Write-Host "AMI $newAmi available. -KeepBox: instance $iid left running."
} else {
  Write-Host "AMI $newAmi available. Terminating $iid..."
  Invoke-Aws ec2 terminate-instances --region $Region --instance-ids $iid | Out-Null
}

Write-Host ""
Write-Host "=== DONE - new golden AMI: $newAmi ==="
Write-Host "Next steps (manual, deliberate):"
Write-Host "  1. Update -AmiId defaults to $newAmi in tool/solver/vcpu-solve.ps1 AND this script."
if (-not $SkipDeepValidate) {
  Write-Host "  2. DEEP gate passed: flip TLSOLVE_DUMP_FMT default 'json' -> 'bin' in"
  Write-Host "     tool/solver/run_solver.dart, update VCPU_RUNBOOK.md, commit (WS1c done)."
} else {
  Write-Host "  2. Deep gate was SKIPPED - do NOT flip the TLSD default off this run."
}
Write-Host "  3. Keep old AMI $AmiId until the first successful solve on $newAmi, then:"
Write-Host "     aws ec2 deregister-image --region $Region --image-id $AmiId (+ delete its snapshot)."
