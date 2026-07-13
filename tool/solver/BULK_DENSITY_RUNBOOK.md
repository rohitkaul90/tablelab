# Full-Density Bulk Campaign — Operator Runbook

**Goal:** all 1,755 canonical flops × each scenario's SPR regimes for the 5 live
scenarios (~26k spots, ≤0.5% expl, 'river' profile, TLSD, NO packs), staged by
value with a spend-approval pause between scenarios. Plan approved 2026-07-11;
fleet re-planned to 4 × r7a.16xlarge after slice-0/1 price data (32xlarge spot
ran ~$3.91/h in 2c vs ~$1.25/h per 16xlarge in 2a/2b — ~35% cheaper per GB-h).

**Stage order:** `srp_late_v_bb` → `srp_middle_v_bb` → `srp_early_v_bb` →
`srp_sb_v_bb` → `3bp_bb_v_btn`.

## Bulk mode — what's different from a curated run

Every bulk launch passes `--no-write` in `-GridArgs`. That flips the launcher
into bulk mode:

- **Boxes never assemble the library** (the grid prints `library write
  SKIPPED`; the health check keys on that instead of `^Wrote `). The ONE
  authoritative `--write` happens at campaign end from the union of all
  shards. Never set `ALLOW_REGIME_DROP`.
- **The results monolith (`freq_grid_results.json`) is FROZEN** — box-side
  `--compact` is skipped and the operator must NOT run `--compact` until the
  campaign ends (a 26k-spot monolith is ~12 GB and would poison every seed).
  The per-scenario `.jsonl` shards are the durable store; `_loadResults` folds
  shards over the monolith in memory, so dry-runs work without compaction.
- **No library pull** at the end of a box run — only the `.jsonl` shards come
  back; periodic sync also pulls shards only.
- **Shard seeding is scenario-scoped** — a box gets the monolith + only its
  own scenario's shard.

## One-time pre-flight

1. Quota: us-east-2 spot vCPU (`L-34B43A08`) ≥ 256 — granted 2026-07-12;
   holds exactly **4 × r7a.16xlarge (64 vCPU each)**. (A two-region split via
   us-east-1 is a fallback only — AMI copy + regional keypair/SG needed there.)
2. **One git worktree per EXTRA concurrent launcher** — N boxes need the
   primary repo + N−1 worktrees, because launchers sharing a folder clobber
   each other's pulled shards and `.remote-staging\`:
   ```powershell
   git worktree add ..\poker_tracker_e1 -b bulk-box2 main
   git worktree add ..\poker_tracker_e2 -b bulk-box3 main
   git worktree add ..\poker_tracker_e3 -b bulk-box4 main
   ```
   Copy the frozen monolith (`tool\solver\freq_grid_results.json`) into each
   worktree's `tool\solver\` once.
3. Disable Windows sleep; one PowerShell window per box.

## Slice sets — pick by fleet size

Two committed, CI-locked partitions of the 1,755 flops (both scenario-agnostic
— the same files serve every stage; see `test/solver/flop_enum_test.dart`):

- **4-way** `tool/solver/flops/slice_mod4_{0..3}.txt` (439/439/439/438,
  round-robin deal) — **the standard set for the 4-box fleet, stages 2–5**:
  one slice per box, all parallel, no work-stealing, no idle-fleet tail.
- **5-way** `tool/solver/flops/slice351_off{0..4}.txt` (351 each, stride) —
  the original 2×32xlarge work-stealing set. Stage 1 ran off0/off1 from it;
  its remainder (off2/off3/off4) finishes on 3 boxes, one slice each.

⚠ **Never mix families within one stage** — a 5-way file unioned with 4-way
files neither covers the 1,755 nor stays disjoint (the zero-pending check
would catch the hole, after the fleet is already terminated).

## Standard srp-stage launch (stages 2–4; stage-1 remainder differs only in files)

Four boxes, one per slice, launched from the primary repo (box 1) and the
three worktrees (boxes 2–4). Box 1 example — boxes 2–4 change only the
`-Flops` file (`slice_mod4_1/2/3`) and the folder they run from:

```powershell
.\tool\solver\vcpu-solve.ps1 -Scenario <sc> `
  -InstanceType r7a.16xlarge -Fallbacks @('r6a.16xlarge','r6i.16xlarge') `
  -Spot -AutoRelaunch -PullAndTerminate -SyncEveryMin 20 `
  -DumpFmt bin -Flops file:tool/solver/flops/slice_mod4_0.txt `
  -DeepClaimGB 50 -CpuOversub 2.0 -HeapMB 48000 -TabulateHeapMB 16000 `
  -GridArgs "--parallel 14 --no-write"
```

Rationale (post streaming-tabulator + decoupling): solve lanes never wait on
tabulates anymore (they fire detached; `TLSOLVE_MAX_PENDING_TABULATES`
default 16 bounds fired tabulates — true /dev/shm residency ≈ 16 + parallel
lanes' own dumps, and that backlog is also the reclaim-loss window on top of
the ≤20-min sync loss), and the streaming tabulator cuts a deep tabulate from
20-40 min to low single-digit minutes with a 16 GB heap (`-TabulateHeapMB
16000`; the eager rollback is the launcher switch `-TabulateEager`, under
which the grid auto-defaults the heap to 80000). `-CpuOversub 2.0` (128-thread budget) leaves headroom so
1-thread tabulate claims don't queue behind 8-thread solve claims;
`--parallel 14` caps solve lanes near the CPU budget. Deep claim 50 GB =
stage-1's validated scenario B (measured solver RSS peaks ~7.8 GB). Per-spot
timeout stays 7200 s. Stage-1 remainder used `slice351_off2/3/4` on 3 boxes.

Stage-1 measured (pre-tabulator-fix, for reference): scenario B ≈ 45
spots/h/box (~$30/slice at 2c pricing); scenario D (claim 30, 28 workers) =
+8% throughput but +63% deep walls and 2 solver crashes → **B is the fleet
config**. With the tabulator fix the modeled rate returns to ~90-100
spots/h/box (validate on the stage-2 canary before fleet launch):

| Config | Slice wall (439 flops) | Stage wall (4 boxes) | Stage cost |
|---|---|---|---|
| B, pre-fix (measured) | ~29 h | ~29 h | ~$145-180 |
| B + streaming/decoupled (modeled) | ~13-16 h | ~13-16 h | ~$65-100 |

## End-of-stage checklist (every scenario)

1. All launchers report `Done. Shards pulled` + terminated. **Sweep the
   region(s)**: `aws ec2 describe-instances --region us-east-2 --filters
   "Name=instance-state-name,Values=pending,running"` → empty.
2. Merge every worktree's shard into the primary repo (concat IS the merge —
   the loader's later-wins fold dedups). Use a BINARY concat, not a
   PowerShell line pipeline (which is slow and re-encodes multi-GB JSONL
   through the ANSI codepage):
   ```powershell
   foreach ($w in 'e1','e2','e3') {
     $src = "..\poker_tracker_$w\tool\solver\freq_grid_results.<sc>.jsonl"
     if (Test-Path $src) {
       cmd /c copy /b "tool\solver\freq_grid_results.<sc>.jsonl"+"$src" "tool\solver\freq_grid_results.<sc>.merged"
       Move-Item -Force "tool\solver\freq_grid_results.<sc>.merged" "tool\solver\freq_grid_results.<sc>.jsonl"
       Remove-Item $src
     }
   }
   ```
3. **Zero-pending check** (primary repo):
   `$env:TLSOLVE_SCENARIO='<sc>'; $env:TLSOLVE_FLOPS='all1755';
   dart --old_gen_heap_size=32000 run tool/solver/freq_grid.dart --sched-dry-run`
   → expect `Solving 0 spot(s)`. Safe at any campaign size: `--sched-dry-run`
   uses the keys-only cache loader (monolith keys + the CURRENT scenario's
   shard streamed line-by-line — it never decodes the multi-GB entry payloads
   or other scenarios' shards). Stragglers → one cleanup launch with
   `-Flops all1755` (cache skips solved); if they're deep timeouts:
   `-Sprs deep -TimeoutS 14400`.
4. Cost guardrail: `dart run tool/solver/solve_report.dart --rate <spot $/vCPU-h>`
   → verify vs the scenario table above. Append a changelog row to
   `GTO_LIBRARY_COVERAGE.md` (mark "pending final commit").
5. **Back up the scenario shard** (gzip → S3 or external drive) — shards are
   the paid, gitignored, irreplaceable artifact.
6. Operator approves the next stage's spend.

## Stage 5 — 3bp (CPU-bound, tiny trees)

Same 4-box pattern with the same `slice_mod4_{0..3}` files — claims are
8–16 GB so nothing is RAM-bound; oversub 2.0 packs the lanes:

```powershell
.\tool\solver\vcpu-solve.ps1 -Scenario 3bp_bb_v_btn `
  -InstanceType r7a.16xlarge -Fallbacks @('r6a.16xlarge','r6i.16xlarge') `
  -Spot -AutoRelaunch -PullAndTerminate -SyncEveryMin 20 `
  -DumpFmt bin -Flops file:tool/solver/flops/slice_mod4_0.txt `
  -CpuOversub 2.0 -HeapMB 48000 `
  -GridArgs "--parallel 20 --no-write"
```

~3.5–4 h, ~$20 all-in. (Same-cost alternative if capacity is tight: ONE box,
`-Flops all1755`, ~14–15 h.)

## Final integration (after stage 5)

1. All 5 shards + frozen monolith in the primary repo; zero-pending green for
   all 5 scenarios; region swept.
2. **Assembly on a cloud box** (the union is ~11 GB of JSON — do NOT attempt
   on the operator machine): gzip shards+monolith (~1.5–2 GB), scp to an
   on-demand ≥512 GB box (r7a.16xlarge on-demand ~$3.7/h),
   `dart --old_gen_heap_size=400000 run tool/solver/freq_grid.dart --write`
   (guards pass — the union is a superset of the committed asset), pull
   `assets/gto_freq_library.json` back, terminate.
3. Sanity: coverage snapshot script; `dart run tool/eval/gen_gto_spots.dart`;
   `flutter test`.
4. **ONE consolidated eval re-baseline** (~$16, gates vs the 2026-07-11
   baseline 99.5/90.1/95.5/86.8 — judge AGGREGATES, not per-spot churn).
5. Ship: branch → PR → /code-review; `git add -f` the library + report.json;
   coverage doc + CLAUDE.md sync.
6. Cleanup: remove the worktrees + `.remote-staging`; keep AMIs + shard
   backups.

## Failure modes

| Symptom | Action |
|---|---|
| Spot reclaim | AutoRelaunch handles it (budget 3, last attempt on-demand); ≤20 min of solves re-run |
| Launcher window dies | Box keeps solving in tmux. ssh in; if `BATCH DONE` in ~/solve.log: pull `freq_grid_results.*.jsonl`, terminate manually |
| `Solving N>0` at stage end | Cleanup pass (see checklist 3) |
| Deep spots ✗ with timeout | `-Sprs deep -TimeoutS 14400` cleanup pass |
| r7a.16xlarge capacity dry | Fallbacks r6a/r6i.16xlarge are in the command; deeper fallback: fewer, bigger boxes (2 × 32xlarge + the 5-way slice set, work-stealing) |
| $/spot drifting above table | Stop launching; investigate util (`[cpu]` lines) + current spot quotes before spending more |
