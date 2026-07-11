# Full-Density Bulk Campaign — Operator Runbook

**Goal:** all 1,755 canonical flops × each scenario's SPR regimes for the 5 live
scenarios (~26k spots, ≤0.5% expl, 'river' profile, TLSD, NO packs), staged by
value with a spend-approval pause between scenarios. Budget ~$840 total
(calibration-proven ~$0.033/spot srp-class; 3bp ~10× cheaper). Full plan
approved 2026-07-11.

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

1. Quota: us-east-2 spot vCPU (`L-34B43A08`) ≥ 256 for two boxes in-region, OR
   us-east-1 ≥ 128 for the two-region split (both requests filed 2026-07-11 —
   use whichever lands; single 128 works at half throughput meanwhile).
2. Two-region only: copy the golden AMI to us-east-1
   (`aws ec2 copy-image --source-region us-east-2 --source-image-id
   ami-0f3cf3bc4ef5c1255 --region us-east-1 --name tablelab-solver-tlsd`),
   import the keypair + create `tablelab-solver-sg` there (both regional).
3. **Second launcher home**: `git worktree add ..\poker_tracker_e1
   feature/bulk-density-prep` — the second box's launcher MUST run from a
   separate worktree (two launchers in one repo clobber each other's pulled
   shards and `.remote-staging\`). Copy the frozen monolith into its
   `tool\solver\` once.
4. Disable Windows sleep; one PowerShell window per box.

## Standard srp-stage launch (stages 1–4)

Five committed slice files partition the 1,755 flops exactly:
`tool/solver/flops/slice351_off{0..4}.txt` (see the partition test in
`test/solver/flop_enum_test.dart`). Work-stealing: each box takes the next
unassigned slice when it finishes one.

```powershell
.\tool\solver\vcpu-solve.ps1 -Scenario srp_late_v_bb `
  -InstanceType r7a.32xlarge -Fallbacks @('r6a.32xlarge','r6i.32xlarge') `
  -Spot -AutoRelaunch -PullAndTerminate -SyncEveryMin 20 `
  -DumpFmt bin -Flops file:tool/solver/flops/slice351_off0.txt `
  -CpuOversub 1.5 -HeapMB 64000 `
  -GridArgs "--parallel 24 --no-write"
```

Second box: same command with the next slice file (+ `-Region us-east-1
-AmiId <copied>` if two-region). Rationale: 1 TB → 8 concurrent deep claims
(800 GB) + shallow/medium backfill; `--parallel 24` is a worker cap above what
admission ever admits; per-spot timeout stays 7200 s (7.5× the deep
calibration wall). Expected: ~12–17 h/slice, ~1.5 days/stage with two boxes,
~$145–175/stage.

## End-of-stage checklist (every scenario)

1. Both launchers report `Done. Shards pulled` + terminated. **Sweep both
   regions**: `aws ec2 describe-instances --region <r> --filters
   "Name=instance-state-name,Values=pending,running"` → empty.
2. Merge the worktree's shard into the primary repo (concat IS the merge —
   the loader's later-wins fold dedups). Use a BINARY concat, not a
   PowerShell line pipeline (which is slow and re-encodes multi-GB JSONL
   through the ANSI codepage):
   ```powershell
   cmd /c copy /b "tool\solver\freq_grid_results.<sc>.jsonl"+"..\poker_tracker_e1\tool\solver\freq_grid_results.<sc>.jsonl" "tool\solver\freq_grid_results.<sc>.merged"
   Move-Item -Force "tool\solver\freq_grid_results.<sc>.merged" "tool\solver\freq_grid_results.<sc>.jsonl"
   ```
   Then delete the worktree copy.
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
   → verify ~$0.033/spot-class. Append a changelog row to
   `GTO_LIBRARY_COVERAGE.md` (mark "pending final commit").
5. **Back up the scenario shard** (gzip → S3 or external drive) — shards are
   the paid, gitignored, irreplaceable artifact.
6. Operator approves the next stage's spend.

## Stage 5 — 3bp (CPU-bound, cheap, one box)

```powershell
.\tool\solver\vcpu-solve.ps1 -Scenario 3bp_bb_v_btn `
  -InstanceType c7a.32xlarge -Fallbacks @('c6a.32xlarge','r7a.16xlarge') `
  -Spot -AutoRelaunch -PullAndTerminate -SyncEveryMin 20 `
  -DumpFmt bin -Flops all1755 -CpuOversub 2.0 -HeapMB 48000 `
  -GridArgs "--parallel 40 --no-write"
```
All claims ≤16 GB; ~6–12 h; ~$79.

## Final integration (after stage 5)

1. All 5 shards + frozen monolith in the primary repo; zero-pending green for
   all 5 scenarios; both regions swept.
2. **Assembly on a cloud box** (the union is ~11 GB of JSON — do NOT attempt
   on the operator machine): gzip shards+monolith (~1.5–2 GB), scp to an
   on-demand ≥512 GB box (or reuse the stage-5 box before terminating),
   `dart --old_gen_heap_size=400000 run tool/solver/freq_grid.dart --write`
   (guards pass — the union is a superset of the committed asset), pull
   `assets/gto_freq_library.json` back, terminate.
3. Sanity: coverage snapshot script; `dart run tool/eval/gen_gto_spots.dart`;
   `flutter test`.
4. **ONE consolidated eval re-baseline** (~$16, gates vs the 2026-07-11
   baseline 99.5/90.1/95.5/86.8 — judge AGGREGATES, not per-spot churn).
5. Ship: branch → PR → /code-review; `git add -f` the library + report.json;
   coverage doc + CLAUDE.md sync.
6. Cleanup: remove the worktree + `.remote-staging`; keep AMIs + shard backups.

## Failure modes

| Symptom | Action |
|---|---|
| Spot reclaim | AutoRelaunch handles it (budget 3, last attempt on-demand); ≤20 min of solves re-run |
| Launcher window dies | Box keeps solving in tmux. ssh in; if `BATCH DONE` in ~/solve.log: pull `freq_grid_results.*.jsonl`, terminate manually |
| `Solving N>0` at stage end | Cleanup pass (see checklist 3) |
| Deep spots ✗ with timeout | `-Sprs deep -TimeoutS 14400` cleanup pass |
| 32xlarge capacity dry in both regions | 2× r7a.16xlarge per region (same quota, ~same deep concurrency), two invocations |
| $/spot drifting above ~$0.04 | Stop launching; investigate util (`[cpu]` lines) before spending more |
