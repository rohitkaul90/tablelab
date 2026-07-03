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
  # Which kScenarios entry/entries to solve (TLSOLVE_SCENARIO for
  # freq_grid.dart). Comma-separate for a sequential BATCH on one box
  # (e.g. 'srp_early_v_bb,srp_middle_v_bb,srp_late_v_bb'); one scenario
  # failing does not stop the rest.
  [string]$Scenario = 'srp_late_v_bb',
  # Extra args passed verbatim to freq_grid.dart (e.g. "--limit 6 --parallel 2").
  [string]$GridArgs = '--parallel 2',
  # Also emit GTO Explorer packs on the box (freq_grid --emit-pack ~/packs) and,
  # under -PullAndTerminate, tar + pull them back into -PackDest\<scenario>\...
  [switch]$EmitPack,
  # Local destination root for pulled packs (created if absent).
  [string]$PackDest = (Join-Path $HOME 'tlpacks'),
  # Dart old-gen heap cap (MB) for the MAIN grid process. Since tabulation now runs
  # in per-spot SUBPROCESSES (tabulate_one.dart), the main process no longer holds a
  # giant dump, so this stays small. The big heap is per-subprocess (-TabulateHeapMB).
  [int]$HeapMB = 24000,
  # Per-SUBPROCESS Dart old-gen heap cap (MB) for each tabulate_one.dart parse - a
  # deep ~15 GB river dump needs a big heap. Each subprocess has its OWN heap/GC, so
  # size --parallel so parallel * (dump + this) < system RAM (watch `free -g`).
  [int]$TabulateHeapMB = 80000,
  # Solver worker threads (8 is the stable max - 16 raced/crashed on wet trees).
  [int]$Threads = 8,
  # Per-spot solver wall cap (s).
  [int]$TimeoutS = 7200,
  # Root EBS size (GB). The AMI snapshot is ~193 GB; grow it for pack-emitting
  # batches (packs + their pull-time tar both land on the root volume - a
  # 3-scenario river batch produces ~60-70 GB of packs). gp3 costs ~cents/day.
  [int]$RootGB = 0,
  [string]$InstanceType = 'r7i.8xlarge',
  # Fall back through these (same 256 GB class) if the chosen type lacks capacity.
  [string[]]$Fallbacks = @('r6i.8xlarge', 'r6a.8xlarge', 'r5.8xlarge'),
  # On-demand by default (spot kept getting reclaimed mid-setup). -Spot opts in.
  [switch]$Spot,
  # Branch to sync onto the box; empty = the CURRENT branch (so a launcher run
  # from a feature branch solves that branch's code, not a stale hardcode).
  [string]$Branch = '',
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
if (-not $Branch) {
  $Branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  if (-not $Branch -or $Branch -eq 'HEAD') { throw "Cannot resolve current branch - pass -Branch." }
}

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
  if ($RootGB -gt 0) {
    $a += @('--block-device-mappings',
      "DeviceName=/dev/sda1,Ebs={VolumeSize=$RootGB,VolumeType=gp3}")
  }
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
# ssh-keygen/ssh write to stderr on the HARMLESS paths (host absent from
# known_hosts; connection refused while the box is still booting). Under -EAP Stop
# a REDIRECTED native stderr is wrapped into a terminating NativeCommandError, so
# wrap these in try/catch and judge by $LASTEXITCODE, not by the error stream.
try { ssh-keygen -R $pubip *> $null } catch { }
$global:LASTEXITCODE = 0
# BatchMode + ServerAlive help, but an ssh can STILL stall in the auth/banner
# window (observed on fresh boots AND once in the -PullAndTerminate poll loop -
# one stuck ssh.exe wedged the whole launcher). So every SSH the launcher
# blocks on runs in a BACKGROUND JOB with a hard Wait-Job timeout: a hung ssh
# is killed and reported as $null (caller decides retry/give-up). The scp
# PULLS remain plain blocking calls: they run only after many healthy ssh
# round-trips on the same connection, and their failure path already leaves
# the box up for a manual retry.
$ssh = @('-i', $key, '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10', '-o', 'BatchMode=yes', '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=2', "ubuntu@$pubip")

function Invoke-SshTimed {
  # Run a remote command with a hard wall-clock cap. Returns an object with
  # .Code/.Out, or $null if the ssh HUNG (killed). A non-zero .Code is a real
  # remote/connection failure, distinct from a hang.
  param([string]$RemoteCmd, [int]$TimeoutSec = 30)
  $j = Start-Job -ScriptBlock {
    param($sshArgs, $cmd)
    $out = ssh @sshArgs $cmd 2>$null
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = "$out" }
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
# Seed the local solve cache: it is GITIGNORED (git archive omits it), and without
# it the box's final _writeLibrary sees only THIS run's scenario, trips the
# scenario-drop guard against the synced library asset (which has the others),
# never prints 'Wrote ' - and -PullAndTerminate would read that as a failed solve.
# Seeding also makes the run resumable and skips already-solved spots.
$cache = Join-Path $repo 'tool\solver\freq_grid_results.json'
if (Test-Path $cache) {
  scp -i $key $cache "ubuntu@${pubip}:~/poker_tracker/tool/solver/freq_grid_results.json"
  if ($LASTEXITCODE -ne 0) { throw "scp freq_grid_results.json (cache seed) failed" }
  Write-Host "Seeded solve cache from local freq_grid_results.json."
}

# -- 5. Start the solve in a detached tmux session ----------------------------
# Build a run-solve.sh locally (LF endings) and scp it, to avoid nested PS->ssh->bash
# quoting. `$HOME is escaped so it stays literal for the remote shell; $Profile etc.
# are interpolated by PowerShell.
$packArgs = if ($EmitPack) { ' --emit-pack /home/ubuntu/packs' } else { '' }
# Scenario batch: comma list -> space list for the bash loop. One scenario
# failing (guard abort, all-spots-failed) must not stop the rest; the poll
# keys on the final 'BATCH DONE' sentinel, NOT on '^Wrote ' (each scenario's
# grid run writes the library, so 'Wrote' fires after the FIRST scenario).
$scenarioList = $Scenario -replace ',', ' '
$solveSh = @"
#!/usr/bin/env bash
cd ~/poker_tracker
export TEXASSOLVER_DIR=`$HOME/texassolver-source
export TEXASSOLVER_BIN=`$HOME/texassolver-source/build/console_solver
# River dumps are ~15 GB each: put scratch on the big RAM tmpfs (the golden AMI's
# 193 GB root EBS fills at useful --parallel, truncating dumps). Raise max_map_count
# for the tabulate subprocesses' big heaps (a big --old_gen_heap_size mmap-crashes
# without it despite free RAM). Clear any orphaned dumps a prior killed run left.
export TMPDIR=/dev/shm
sudo sysctl -w vm.max_map_count=2000000 >/dev/null 2>&1 || true
rm -rf /dev/shm/tlsolve_* /mnt/scratch/tlsolve_* 2>/dev/null || true
{
for SC in $scenarioList; do
  echo "=== SCENARIO `$SC ==="
  TLSOLVE_SCENARIO=`$SC TLSOLVE_PROFILE=$Profile TLSOLVE_ACCURACY=0.5 TLSOLVE_TIMEOUT_S=$TimeoutS TLSOLVE_MAXITER=400 TLSOLVE_THREADS=$Threads TLSOLVE_TABULATE_HEAP_MB=$TabulateHeapMB dart --old_gen_heap_size=$HeapMB run tool/solver/freq_grid.dart $GridArgs$packArgs || echo "SCENARIO `$SC FAILED"
done
echo "BATCH DONE"
} 2>&1 | tee ~/solve.log
"@
$localSh = Join-Path $env:TEMP 'run-solve.sh'
[IO.File]::WriteAllText($localSh, ($solveSh -replace "`r`n", "`n"))
scp -i $key $localSh "ubuntu@${pubip}:~/run-solve.sh"
if ($LASTEXITCODE -ne 0) { throw "scp run-solve.sh failed" }
ssh @ssh 'tmux kill-session -t solve 2>/dev/null; tmux new -d -s solve "bash ~/run-solve.sh"'
if ($LASTEXITCODE -ne 0) { throw "failed to start the tmux solve session" }
Write-Host ""
Write-Host "Solve started on $iid ($itype): TLSOLVE_SCENARIO=$Scenario TLSOLVE_PROFILE=$Profile $GridArgs$packArgs"
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
  # The completion sentinel is 'BATCH DONE' (emitted after the scenario loop -
  # '^Wrote ' fires after the FIRST scenario of a batch, far too early). Check
  # it BEFORE 'dead' so a clean finish (session ends right after the echo)
  # still reads as success. Each poll goes through Invoke-SshTimed: a HUNG poll
  # ssh is killed and retried (this exact wedge ate a finished Cycle A run -
  # the solve completed but the launcher never noticed). Only give up after
  # many CONSECUTIVE failures (box unreachable ~7 min), never on one blip.
  $failures = 0
  do {
    Start-Sleep 30
    $r = Invoke-SshTimed "if grep -q 'BATCH DONE' ~/solve.log 2>/dev/null; then echo wrote; elif tmux has-session -t solve 2>/dev/null; then echo running; else echo dead; fi"
    if ($r -and $r.Code -eq 0 -and "$($r.Out)".Trim()) {
      $failures = 0
      $state = "$($r.Out)".Trim()
    } else {
      $failures++
      $state = 'running' # transient hang/blip - keep polling
      if ($failures -ge 12) { $state = 'unreachable' }
    }
  } while ($state -eq 'running')

  if ($state -eq 'unreachable') {
    Write-Warning "Lost contact with the box (12 consecutive failed polls). Instance $iid is"
    Write-Warning "LEFT RUNNING - check it over SSH, pull manually, then terminate:"
    Write-Warning "  aws ec2 terminate-instances --region $Region --instance-ids $iid"
    return
  }

  if ($state -ne 'wrote') {
    $r = Invoke-SshTimed "tail -n 30 ~/solve.log" -TimeoutSec 60
    if ($r) { Write-Host $r.Out }
    Write-Warning "Solve ended WITHOUT writing the library (crash / OOM / all spots failed /"
    Write-Warning "a _writeLibrary guard aborted). Instance $iid is LEFT RUNNING for triage -"
    Write-Warning "do NOT trust a pulled library. Inspect above, then terminate when done:"
    Write-Warning "  aws ec2 terminate-instances --region $Region --instance-ids $iid"
    return
  }

  # Batch health: the sentinel fires even if individual scenarios failed (a
  # guard abort in one must not strand the others' results). Require at least
  # ONE library write, and surface per-scenario failures loudly.
  $chk = Invoke-SshTimed "grep -c '^Wrote ' ~/solve.log; grep -c 'SCENARIO .* FAILED' ~/solve.log" -TimeoutSec 60
  $wroteCount = 0
  $scenarioFails = 0
  if ($chk) {
    $nums = @("$($chk.Out)" -split "`r?`n" | Where-Object { $_ -match '^\d+$' })
    if ($nums.Count -ge 1) { $wroteCount = [int]$nums[0] }
    if ($nums.Count -ge 2) { $scenarioFails = [int]$nums[1] }
  }
  if ($wroteCount -eq 0) {
    $r = Invoke-SshTimed "tail -n 30 ~/solve.log" -TimeoutSec 60
    if ($r) { Write-Host $r.Out }
    Write-Warning "BATCH DONE but NO library write happened (every scenario failed or"
    Write-Warning "aborted on a guard). Instance $iid LEFT RUNNING for triage - do not"
    Write-Warning "trust a pulled library. Terminate when done:"
    Write-Warning "  aws ec2 terminate-instances --region $Region --instance-ids $iid"
    return
  }
  if ($scenarioFails -gt 0) {
    Write-Warning "$scenarioFails scenario(s) FAILED in the batch - the pulled library"
    Write-Warning "holds only the successful ones (grep 'SCENARIO .* FAILED' ~/solve.log"
    Write-Warning "on the box, or the pulled log). The library write guards still ran."
  }
  $r = Invoke-SshTimed "tail -n 3 ~/solve.log" -TimeoutSec 60
  if ($r) { Write-Host $r.Out }
  Write-Host "Pulling library + cache back..."
  # Relative dest paths from the repo root (Push-Location) - a 'C:/...' absolute path
  # can trip scp's host:path colon parsing on some builds. Guard ALL pulls: only
  # terminate if every one succeeded, else leave the box up so the solve output (and
  # the resumable freq_grid_results.json) isn't destroyed.
  Push-Location $repo
  try {
    scp -i $key "ubuntu@${pubip}:~/poker_tracker/assets/gto_freq_library.json" 'assets/gto_freq_library.json'
    $okLib = ($LASTEXITCODE -eq 0)
    scp -i $key "ubuntu@${pubip}:~/poker_tracker/tool/solver/freq_grid_results.json" 'tool/solver/freq_grid_results.json'
    $okCache = ($LASTEXITCODE -eq 0)
  } finally { Pop-Location }
  $okPacks = $true
  if ($EmitPack) {
    # Packs are emitted only for NEWLY-solved spots: a fully-cached run never
    # creates ~/packs, and failing the pull on that would leave the box
    # running (billing) over a nonexistent optional output. Probe first.
    $probe = Invoke-SshTimed 'test -d ~/packs && echo yes || echo no' -TimeoutSec 60
    if (-not $probe -or $probe.Code -ne 0) {
      Write-Warning "Could not probe ~/packs on the box - skipping the pack pull."
      Write-Warning "If packs were expected, pull manually before terminating."
      $okPacks = $false
    } elseif ("$($probe.Out)".Trim() -ne 'yes') {
      Write-Warning "No ~/packs on the box (all spots cached? pack emission failed?)"
      Write-Warning "- nothing to pull; continuing to terminate."
    } else {
    # Tar on the box (thousands of small chunk files - a bare scp -r is slow and
    # fragile), pull one archive, extract into -PackDest with Windows' bsdtar.
    Write-Host "Pulling explorer packs (this is the multi-GB step)..."
    $tarR = Invoke-SshTimed 'tar -czf ~/packs.tgz -C ~/packs .' -TimeoutSec 1800
    $okPacks = ($null -ne $tarR -and $tarR.Code -eq 0)
    if ($okPacks) {
      New-Item -ItemType Directory -Force $PackDest | Out-Null
      $localTgz = Join-Path $env:TEMP 'tlpacks-pull.tgz'
      scp -i $key "ubuntu@${pubip}:~/packs.tgz" $localTgz
      $okPacks = ($LASTEXITCODE -eq 0)
      if ($okPacks) {
        tar -xzf $localTgz -C $PackDest
        $okPacks = ($LASTEXITCODE -eq 0)
        if ($okPacks) { Remove-Item $localTgz -Force }
      }
    }
    } # end packs-exist branch
  }
  if (-not ($okLib -and $okCache -and $okPacks)) {
    Write-Warning "A pull FAILED (library=$okLib cache=$okCache packs=$okPacks). Instance $iid"
    Write-Warning "LEFT RUNNING so the solve output isn't lost - retry the pull, then terminate:"
    Write-Warning "  aws ec2 terminate-instances --region $Region --instance-ids $iid"
    return
  }
  Write-Host "Terminating $iid..."
  Invoke-Aws ec2 terminate-instances --region $Region --instance-ids $iid | Out-Null
  Write-Host "Done. Library pulled (review 'git diff', then 'git add -f' it)$(if ($EmitPack) { ", packs in $PackDest" }) + instance terminated."
}
