# vCPU Solve Runbook — big-RAM Linux box for GTO library coverage

**What this is:** the operator runbook for solving GTO-frequency-library coverage on a
high-core / high-RAM Linux cloud box, when the local 32 GB Windows machine can't (deep-SPR
/ river OOM) or would be too slow. The grid (`freq_grid.dart`) is *embarrassingly parallel*,
so throughput scales ~linearly with cores; 768 GB RAM unblocks the deep-cash / river trees.

The licensed TexasSolver CPU source **builds on Linux** (GCC flags, vendored `ext/` deps;
only quirk = `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`, same as Windows). No engine change, no
pruning, license-clean (the source is never committed).

Related: `GTO_LIBRARY_COVERAGE.md` (scope map — update after every cycle), `README.md`
(harness overview), `SOLVER_PRIMER.md` (how the solver works), memory `dce_q1_phase2b_turn`
(phase-2b history + the scaling research that produced this runbook).

> **FULL-DENSITY BULK CAMPAIGN → see `BULK_DENSITY_RUNBOOK.md`.** Bulk runs pass
> `--no-write` in `-GridArgs`, which flips the launcher into bulk mode (frozen results
> monolith, shard-only sync/pull, no box-side library write/pull, scenario-scoped shard
> seeding). This runbook's fast path stays the reference for CURATED (26-flop / pack)
> cycles.

> **TABULATOR (2026-07-13): TLSD tabulation is STREAMING by default** — nodes decode
> on demand in walk order (bit-identical cells to the old eager tree; locked by tests),
> so `-TabulateHeapMB` defaults to the grid's 16 GB and deep tabulates drop from
> 20-40 min (saturated 64-core boxes) to low single-digit minutes. Tabulates also run
> DETACHED from solve lanes (`TLSOLVE_MAX_PENDING_TABULATES`, default 32, bounds
> /dev/shm dumps). Rollbacks: `TLSOLVE_TABULATE_EAGER=1` (+ `-TabulateHeapMB 80000`)
> restores the eager path; `TLSOLVE_MAX_PENDING_TABULATES=1` re-serializes lanes.
> JSON/`--emit-pack` runs are unaffected (JSON path unchanged).

---

## ⚡ Fast path — `tool/solver/vcpu-solve.ps1`

Once a **golden AMI** exists (toolchain + built `console_solver` + deps baked in — §8 below),
the launcher script collapses §1–6 into one command: launch from the AMI (capacity fallback),
sync the current branch, start the solve in a detached tmux session. It bakes in the river
Dart-heap flag and the 8-thread cap.

```powershell
# River re-trial (read ~/solve.log + free -g over SSH; do NOT auto-pull a --limit run):
.\tool\solver\vcpu-solve.ps1 -GridArgs "--limit 6 --parallel 2"

# Full solve, fire-and-forget (wait → pull library → terminate):
.\tool\solver\vcpu-solve.ps1 -GridArgs "--parallel 2" -PullAndTerminate
```

Key params: `-Profile turn|river` (default river), `-GridArgs`, `-InstanceType` (+ `-Fallbacks`),
`-Spot` (opt-in; see spot resilience below), `-HeapMB` (default 24000 — tabulation runs in
per-spot subprocesses, `-TabulateHeapMB`), `-Branch`, `-AmiId` (default the golden AMI),
`-PullAndTerminate` (FULL solves only — it refuses to auto-pull a `--limit` partial). The
script prints ready-to-paste watch / tail / RAM / pull / terminate commands. The manual
runbook below is the fallback when there's no golden AMI yet, or for debugging a launch.

**CPU oversubscription (`-CpuOversub`, 2026-07-10):** solves CLAIM 8 threads but drive only
~4-5 (calibration measured ~50-55% CPU util on both box classes), so the admission budget
can oversubscribe cores: `-CpuOversub 1.6` sets `TLSOLVE_CPU_OVERSUB` (a multiplier on
nproc; `-CpuBudget` is the absolute override). Size `--parallel` above `cores×oversub/8`
so the scheduler — not the worker pool — is the binding cap. The `-PullAndTerminate` poll
prints a `[cpu] <load> / <cores>` line each interval; load/cores nearing ~0.8-0.9 (from
~0.5) = the tune is working. RAM claims still gate the deep class.

**Spot resilience (WS3, 2026-07-09):** under `-PullAndTerminate` the launcher stages the
checkpoint shards locally every `-SyncEveryMin` (default 10) into
`tool\solver\.remote-staging\`, and `-AutoRelaunch` relaunches on a CONFIRMED spot reclaim
(StateReason `Server.SpotInstanceTermination` or the box's `~/SPOT_RECLAIM_NOTICE` marker,
stamped by an IMDSv2 watcher in run-solve.sh), reseeding the freshest staged shards;
`-RelaunchBudget` (default 3) caps retries and the final attempt drops `-Spot`. A crash
still leaves the box up for triage. This makes `-Spot` (~25–35% of the on-demand rate) the
sensible default for bulk runs:

```powershell
.\tool\solver\vcpu-solve.ps1 -GridArgs "--parallel 16" -Spot -AutoRelaunch -PullAndTerminate
```

---

## 0. Prerequisites (one-time, before you start)

- The **licensed TexasSolver `source` dir** on your Windows machine (the one with
  `resources/` and the EV patches already applied). The EV patches aren't needed for the
  frequency library (it reads strategies, not EV), but they compile fine under GCC and ride
  along with the source.
- An **AWS account** with spot access, an SSH key pair, and a default VPC.
- The repo pushed to a remote you can `git clone` on the box (or `rsync` it up).

---

## 1. Provision the box

**Target: `r7a.24xlarge` spot — 96 vCPU / 768 GB.** (Any 64–192 vCPU / 256–512 GB box works;
deep-cash + river specifically want the big RAM.)

- AMI: **Ubuntu 24.04 LTS**.
- Root EBS: **≥200 GB gp3** — the per-solve dump JSONs are multi-MB and there are
  `--parallel N` of them at once. `TMPDIR` must live on this disk.
- Spot request: one-time or persistent; pick the cheapest AZ in your region
  (~$1.50–2.50/hr spot vs ~$6 on-demand). **Set a max price ≤ on-demand.**
- Security group: inbound **SSH (22) from your IP only**.

> Spot caveat: a spot instance can be reclaimed with a 2-minute warning. The grid is
> **resumable per-spot** via `freq_grid_results.json`, so a reclaim costs at most the
> in-flight spots. For a long river run, consider on-demand or a persistent spot request.

---

## 2. Toolchain (on the box)

```bash
sudo apt update && sudo apt install -y build-essential cmake git rsync unzip tmux \
  apt-transport-https wget gnupg
# Dart SDK
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub \
  | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' \
  | sudo tee /etc/apt/sources.list.d/dart_stable.list
sudo apt update && sudo apt install -y dart
# Flutter is NOT required — the harness runs under plain `dart run`.

# Big-disk scratch for solver dumps
sudo mkdir -p /mnt/scratch && sudo chown ubuntu:ubuntu /mnt/scratch
```

---

## 3. Move the source + repo up

```bash
# Licensed TexasSolver source (NOT in the repo — by license). From the Windows box:
rsync -az --info=progress2 \
  "/c/Users/rhtk1/Downloads/TexasSolver_Customer_Delivery_.../source/" \
  ubuntu@<ip>:~/texassolver-source/

# The repo:
ssh ubuntu@<ip> 'git clone <repo-url> ~/poker_tracker && cd ~/poker_tracker && dart pub get'
```

(Option B — resume instead of fresh solve — also rsync your gitignored
`tool/solver/freq_grid_results.json` up now. See §6.)

---

## 4. Build the solver (Linux)

```bash
cd ~/texassolver-source
mkdir -p build && cd build
cmake .. -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)            # minutes on 96 vCPU
# → ~/texassolver-source/build/console_solver
ls -la console_solver     # confirm it exists
```

If the build can't find `resources/` at solve time, the binary resolves them relative to
its working dir — the harness already sets `workingDirectory: <sourceDir>`, so keep the
`build/` dir inside the source tree (don't move the binary out).

---

## 5. Point the harness at it

```bash
cd ~/poker_tracker
export TEXASSOLVER_DIR=~/texassolver-source
export TEXASSOLVER_BIN=~/texassolver-source/build/console_solver   # the Linux binary
export TMPDIR=/mnt/scratch                                          # big-disk dumps
```

`_solverBin()` (run_solver.dart) auto-detects Linux → `build/console_solver`, so
`TEXASSOLVER_BIN` is belt-and-suspenders but explicit is safest.

---

## 6. Solve — fresh (A) vs resume (B)

> **FOOTGUN — read this first.** `_writeLibrary` rebuilds the **entire** library from
> whatever profile-matching spots sit in `freq_grid_results.json`. If you solve only the
> *new* spots (e.g. just the deep-SPR ones) with an empty cache, the rebuild produces a
> library missing the shallow/medium cells and **clobbers the shipped library**. So:

**Option A — fresh full re-solve (recommended; simplest, complete library).**
Solve every regime so the rebuilt library is whole.

```bash
rm -f tool/solver/freq_grid_results.json     # start clean
# Smoke: --limit 3 covers the first {shallow,medium,deep} of one flop (incl. a deep spot)
TLSOLVE_ACCURACY=0.5 TLSOLVE_THREADS=8 dart run tool/solver/freq_grid.dart --limit 3

# Validate at low parallelism BEFORE scaling (the dce_q1_phase2b_turn hard rule):
TLSOLVE_ACCURACY=0.5 TLSOLVE_TIMEOUT_S=3000 TLSOLVE_MAXITER=400 TLSOLVE_THREADS=8 \
  dart run tool/solver/freq_grid.dart --parallel 2

# Full run, in tmux so an SSH drop doesn't kill it:
tmux new -s solve
TLSOLVE_ACCURACY=0.5 TLSOLVE_TIMEOUT_S=3000 TLSOLVE_MAXITER=400 TLSOLVE_THREADS=8 \
  dart run tool/solver/freq_grid.dart --parallel 12 | tee solve.log
# detach: Ctrl-b d   ·   reattach: tmux attach -t solve
```

**Option B — resume (faster; only solves the new spots).**
Only safe if you rsync'd the existing `freq_grid_results.json` up in §3 — then the grid
skips cached spots and solves just the additions, and the rebuild folds in everything.

```bash
# (results.json already present from the rsync)
TLSOLVE_ACCURACY=0.5 TLSOLVE_TIMEOUT_S=3000 TLSOLVE_MAXITER=400 TLSOLVE_THREADS=8 \
  dart run tool/solver/freq_grid.dart --parallel 12 | tee solve.log
```

### Run-config reference

| Env var | This run | Meaning |
|---|---|---|
| `TLSOLVE_ACCURACY` | `0.5` | exploitability % stop threshold |
| `TLSOLVE_TIMEOUT_S` | `3000` | per-spot wall cap. **Deep/river may need higher** — bump if deep spots don't reach 0.5% |
| `TLSOLVE_MAXITER` | `400` | CFR iteration cap |
| `TLSOLVE_THREADS` | `8` | solver worker threads per spot. **16 crashed ~48%** on wet turn-raise trees (concurrency race, not OOM) — keep 8. Note threads are NOT a throughput lever anyway (8→16t only ~1.2–1.3×, memory-bandwidth-bound) — more concurrent spots is |
| `TLSOLVE_DUMP_FMT` | `bin` | **TLSD binary dump** (2026-07-09): ~10× smaller, small-heap parse — the pre-TLSD ~15 GB JSON needed a ~150 GB heap and capped `--parallel` at ~5/TB. `json` = the oracle + REQUIRED for `--emit-pack`; `both` = one solve, two dumps (validate_dump.dart) |
| `TLSOLVE_FLOPS` | `rep` | flop set: `rep` (26 curated) / `all1755` (full density) / `file:<path>` (slice across boxes) |
| `TLSOLVE_RAM_BUDGET_GB` | MemTotal×0.85 | RAM-aware scheduler budget (spot_sched.dart): solve/parse phases claim (GB, threads); deep claims throttle concurrency, shallow packs around them (LPT deep-first) |
| `TLSOLVE_MAX_SPOT_GB` | unset | SKIP spots predicted above this (a 256 GB box grinds shallow/medium, a 1 TB box takes deep) |
| `--parallel N` | high | worker cap only — the scheduler's budget admission does the real throttling, so set it generously (e.g. 16–24 on 128 vCPU) and let RAM claims govern. `--sched-dry-run` prints the planned packing |

Concurrency model: one orchestrator process, a bounded worker pool; each solved spot
appends ONE line to its scenario's `freq_grid_results.<scenario>.jsonl` shard (O(spot)
checkpoint — the old whole-file rewrite was O(total) and already 128 MB/spot at 312 spots);
`--compact` folds shards into `freq_grid_results.json` (run before seeding a box; the box
run-script compacts automatically before its `BATCH DONE`). Per-call temp dirs prevent dump
collisions. Thread count + dump format are excluded from the cache tag (they don't change
the GTO result).

---

## 7. Validation gate (before trusting the library)

Run the snapshot Python from `GTO_LIBRARY_COVERAGE.md` against the new
`assets/gto_freq_library.json`, then check:

1. **Faithfulness** — a turn OOP `first_to_act` cell is **NOT** ~80% donk-lead (confirms
   the raise-bearing 'turn' tree stayed faithful; ~80% donk = the distorted raise-free
   regime leaked in).
2. **New-regime presence** — the snapshot's `spr_bucket` Counter actually shows the new
   bucket (`deep` for this cycle) with non-trivial mass.
3. **Reach mass** — fraction of cells below `minMass=8` is small (serve-eligible %); a high
   suppressed fraction means the tree rarely reaches those nodes.
4. **Exploitability** — grep `solve.log`: every spot converged ≤ target (0.5%), no spot
   silently fell back to a high-expl timeout.

---

## 8. Pull back → commit → eval → teardown

```bash
# From Windows — pull the rebuilt library (+ the cache for the record):
rsync -az ubuntu@<ip>:~/poker_tracker/assets/gto_freq_library.json ./assets/
rsync -az ubuntu@<ip>:~/poker_tracker/tool/solver/freq_grid_results.json ./tool/solver/
```

- `git add -f assets/gto_freq_library.json` (the assets dir is force-added; cache stays
  gitignored).
- **Refresh `tool/solver/GTO_LIBRARY_COVERAGE.md`** — re-run its snapshot block, update the
  tables + structural-gap section, add a Changelog row. This is part of "done"
  (memory `gto-coverage-doc-maintenance`).
- **Eval re-baseline** — full `tool/eval/score.ts` + commit `report.json`.
  ⚠️ **Run on a SEPARATE Anthropic key** — the eval shares the prod monthly cap
  (memory `eval_prod_shared_cap`); a heavy run can 400 live `analyze-hand`.
- **No `analyze-hand` redeploy needed for a library-only change** — the GTO FACT is computed
  **client-side** in `villain_range` (loads the asset, sends it as `equityFacts`); the
  function never reads the library. Web auto-deploys via the assets change; mobile via the
  next AAB. (Only redeploy if you also changed `supabase/functions/`.)
- **Terminate the spot instance** — *terminate*, not stop (a stopped spot still bills EBS).
  Snapshot/rsync anything you want to keep first.

---

## 9. Adapting this runbook to other cycles

This cycle = **deep-SPR** (`kSprReps` gained `'deep': 15.0`; same BTN-vs-BB scenario, same
'turn' profile — minimal code change). Future cycles need more `freq_grid.dart` /
`run_solver.dart` prep before provisioning:

| Cycle | Code prep | Notes |
|---|---|---|
| **River** | ✅ DONE — full river solved 2026-07-01 (78 spots, 0 failures). The 2026-06-30 trial's "parse is the blocker" finding was fixed twice over: first the per-spot SUBPROCESS tabulator (commit 0130619), then **TLSD binary dumps (2026-07-09)** which shrink the parse itself ~10×/25-50× heap — see the run-config table. Historical trial detail lives in `memory/dce_river_trial`. | JSON-era river rules (200 GB main heap, 150 GB tabulate heaps, --parallel ≤5/TB) are OBSOLETE under `TLSOLVE_DUMP_FMT=bin`; keep them only for `--emit-pack` (JSON) runs |

### Golden AMI + refresh

**Golden AMI:** `ami-0f3cf3bc4ef5c1255` (`tablelab-solver-tlsd-20260709`, us-east-2) bakes
the toolchain + the **TLSD-patched** `console_solver` + flutter deps — launch from it to
skip §2 + §4 entirely; just `git archive` the branch over the baked-in repo for code
changes. Baked 2026-07-09 after the deep dual-dump gate passed (15.1 GB JSON vs 1.58 GB
TLSD, 2,123 servable cells, 0 mismatches); `TLSOLVE_DUMP_FMT` defaults to `bin` from the
same date. Predecessor `ami-04c312a0a89b077c2` (pre-TLSD) — deregister + delete its
snapshot after the first successful solve on the new AMI.

Refresh the AMI (future solver-source changes) with
**`tool/solver/refresh-ami.ps1`** (WS1c cloud step): it launches a 256 GB box from the
current golden AMI, syncs the patched solver source (git archive from the LOCAL-ONLY source
repo — vsbuild/ is gitignored so the archive is clean), rebuilds `console_solver` on Linux
(§4's cmake flags), then gates the bake behind (1) a dual-dump SMOKE equivalence and (2) the
**DEEP gate** — one real srp_late deep spot (SPR 15, river profile) solved once with
`TLSOLVE_DUMP_FMT=both`, JSON vs TLSD cells compared (the ~15 GB-dump class TLSD exists
for; ~60–90 min). Passing bakes `tablelab-solver-tlsd-<date>` and terminates the box; any
failure leaves the box up for triage (`~/ami-validate.log`). ~$6 all-in.

After a successful refresh (manual, deliberate): update the `-AmiId` defaults
(vcpu-solve.ps1 + refresh-ami.ps1) and keep the OLD AMI until the first successful solve
on the new one, then deregister it + delete its snapshot. (The one-time
`TLSOLVE_DUMP_FMT` json→bin default flip happened with the 2026-07-09 refresh — the WS1c
deep gate was its criterion.)
| **New scenario** (3-bet / other openers / BvB) | Parameterize `scenarioRanges()` beyond hardcoded BTN-vs-BB; thread a scenario key through the spot/library | Biggest gap (1 of ~8 scenarios); largest code change |
| **`facing_allin` relabel** | Relabel all-ins like the live `facing_bet_*`/`facing_raise` path so shove cells are reachable | Cheap; bundle with any solve |
| **Asymmetric per-street SPR** | Match the live asymmetric-stack lookup against the symmetric offline solve | Pre-existing latent miss (flop too) |

Provisioning, build, run mechanics, validation, and teardown (§1–8) are identical
regardless of target — only the `kSprReps` / `kDumpRounds` / profile / scenario knobs change.
