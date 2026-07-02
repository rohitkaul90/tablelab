# GTO Frequency Library — Coverage & Roadmap

**What this is:** the living scope map of `assets/gto_freq_library.json` — the offline
TexasSolver-derived GTO action-frequency library that grounds the live
`[HEURISTIC — GTO frequency]` FACT in `analyze-hand`. It records, numerically, what
the library covers and what's left, so we can scope solve cycles and judge ROI.

> **MAINTENANCE:** update this doc after **any solve cycle that changes coverage**
> (new street, scenario, SPR regime, bet grid, or a re-solve). Re-run the snapshot
> command below, refresh the tables, and add a row to the Changelog. Keep it honest —
> coverage is a credibility instrument, like the eval baseline.

Related: design = `launch/GTO_FREQUENCY_LIBRARY.md` (gitignored, local); tooling =
`tool/solver/freq_grid.dart` (solve) + `freq_tabulate.dart` (tabulate) +
`run_solver.dart` (TexasSolver bridge); live lookup = `lib/equity/gto_frequency_library.dart`.

---

## Snapshot — as of 2026-07-01 (river added)

`scenario = srp_late_v_bb` (BTN open vs BB call, heads-up, single-raised) — **the only
scenario**. `11,764` cells total, `11,400` **serve-eligible** (clear lookup `minMass=8`) = **97%**.

| Attribute | Covered | Distribution (serve-eligible) | Gap |
|---|---|---|---|
| **Street** | **flop + turn + river** | turn 54% / river 23% / flop 23% | none (full postflop; river added 2026-07-01) |
| **Position** | IP + OOP | ip 51% / oop 49% | none (HU complete) |
| **SPR bucket** | shallow (~25bb) + medium (~40bb) + **deep (~100bb)**; committed appears on turn+river (post bet-call) | deep 28% / medium 27% / shallow 27% / committed 18% | none across the SRP band |
| **Texture** | all **48/48** cells (3 suit × 2 pairing × 4 high-card × 2 connectedness) | fully spanned | none (flop+turn+river together cover the whole space) |
| **Facing node** | all 6: first_to_act, facing_check, facing_bet_{small,mid,big}, facing_raise | big 26 / raise 20 / mid 19 / check 13 / fta 13 / small 10 | per-street size seam (below); `facing_allin` = 0 cells |
| **Hand class** | all 5: air, weakDraw, strongDraw, marginalMade, strongMade | 15–26% each (balanced) | none |

**Per-street facing seam:** the solve bets flop 33/75 (→ small/big) and turn+river 66 (→ mid),
so per-street the native faced-bet sizes are coarse; raises + the cross-street merge fill
the rest. All 6 buckets exist in aggregate.

**Per-street × SPR:** every street now carries all its SPR buckets — flop shallow/medium/deep
(~880 each); turn shallow/medium/deep (~1,600 each) + committed (~1,380); river
shallow/medium/deep/committed (~655 each). The 'river' bet profile (dump_rounds 3) makes
river check-raise available, so river frequencies are faithful (not donk-distorted).

**`facing_allin` mismatch — ✅ FIXED in code 2026-07-02** (`freq_tabulate._facingActLabel`,
tested): a faced all-in now labels like the live `_heroFacing` — opening shove →
`facing_bet_<bucket>`, shove over a wager → `facing_raise`. Takes effect from the NEXT
solve's tabulation (cached cells unchanged; 0 such cells existed, so nothing to migrate).
Matters most for the 3-bet-pot scenario (shoves are routine at SPR ~1–4).

**Asymmetric-SPR — ✅ RESOLVED BY CONVENTION (assessed 2026-07-02, no code change):**
the live lookup's SPR uses the standard effective-stack convention (min of hero and the
shortest simulated villain ÷ pot), which is exactly the symmetric offline solve's
semantics — a live asymmetric hand at effective SPR X plays the same tree as the
symmetric solve at SPR X, since the deeper stack's extra chips can never go in.
TexasSolver only accepts one symmetric `set_effective_stack`, so the residual (the
deeper player's leverage/implied-threat asymmetry) is unsolvable offline and is the
standard industry approximation. Not a lookup bug; removed from the roadmap.

---

## Structural gaps — the real roadmap (ranked by size)

The snapshot above is **one slice** of the intended product surface. As a fraction of the
full surface (≈8 scenarios × 3 streets × 4 SPR regimes × HU/multiway × chip-EV/ICM), this
is a **~low-single-digit-to-15% slice — but the single highest-frequency one** (BTN-vs-BB
SRP is the most common HU postflop spot).

1. **Scenario ≈ 1 of ~8** — only BTN-vs-BB single-raised. **Zero** for 3-bet/4-bet pots,
   other openers (UTG/CO/SB), blind-vs-blind, limped pots. *Biggest gap now that river is done.*
2. ~~**River = 0%**~~ — ✅ **covered 2026-07-01** (BTN-vs-BB SRP, all SPR incl. deep;
   'river' profile / dump_rounds 3, so river check-raise is faithful; solved on a 128-vCPU /
   1 TB r7a.32xlarge, 78 spots, 0 failures, all ≤0.5% expl). Full postflop (flop+turn+river)
   for BTN-vs-BB is now complete. Remaining river gap: any non-BTN-vs-BB scenario.
3. **Multiway = 0%** — HU only. Multiway is handled *directionally* by the MDF FACT, no freqs.
4. ~~**Deep cash (100bb, SPR ~15–17) = 0%**~~ — ✅ **covered 2026-06-30** (deep SPR 15
   added for BTN-vs-BB SRP; flop+turn on an r7a.8xlarge / 256 GB spot box, then **river at
   deep SPR added 2026-07-01**). Remaining deep gap: deep for any non-BTN-vs-BB scenario.
5. **Game type: chip-EV only, no ICM.** No cash/tournament axis. Most applicable to
   tournaments + short cash; ICM spots (bubble, FT, pay jumps) **not modeled**.

**Now that BTN-vs-BB is complete across all three streets and all SPR regimes, the next
solve cycles are all about WIDTH (new scenarios), not DEPTH — see the roadmap.**

---

## Roadmap & compute (next solve cycles)

Real per-spot timings this run (8 threads, local): shallow ~250–490s, medium ~750–1,430s,
**~700s avg**. The grid is *embarrassingly parallel* (independent spots).

| Milestone | Spots | Local (serial-ish) | Big-vCPU Linux | Needs |
|---|---|---|---|---|
| ✅ flop+turn, BTN-vs-BB (shallow+medium) | 52 | ~several h | ~50 min @ 96-vCPU | — |
| ✅ + deep SPR (same scenario, flop+turn) | 26 | **blocked (OOM @32 GB)** | 65 min @ r7a.8xlarge / 256 GB, --parallel 4 | big RAM ✓ |
| ✅ + River (same scenario, all SPR) | 78 | **impractical (~15–30 h)** | **~6 h @ r7a.32xlarge / 1 TB, --parallel 5** | **big RAM + subprocess tabulator** |
| + each new scenario (3-bet / other openers / BvB) | ~78 each | ~10+ CPU-h each | ~50 min–hours each | — |
| + ICM | — | — | feasible | — |

**The lever:** a 64–192 vCPU, 256 GB–1 TB Linux box → ~8–24× throughput + unblocks
deep-cash/river. **River specifically needs 1 TB RAM + the per-spot SUBPROCESS tabulator**
(commit 0130619): deep river dumps are ~15 GB on disk → ~150 GB Dart heap to parse, so the
old `Isolate.run` shared one GC and stalled (~2 spots/hr); a process per spot gives each its
own heap → `--parallel` parallelizes across cores. That capped concurrency at ~5 (5×150 GB
< 1 TB) — the remaining lever for higher parallelism is a streaming/SAX tabulator (lower
per-parse memory). License-clean — the CPU source builds on Linux (GCC flags, vendored deps;
pass `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`). No pruning, no engine change.

**Next solve cycles (all WIDTH — river/deep are done for BTN-vs-BB):** scenario order
(decided 2026-07-02, rationale in `launch/GTO_EXPLORER.md` §7): **Cycle A =
`3bp_bb_v_btn`** (BB 3-bets vs BTN open — SPR ~1–4 → small trees, LOCAL solve; code
prep DONE 2026-07-02: multi-scenario grid via `TLSOLVE_SCENARIO`, scenario defined,
facing_allin relabel, live `_deriveScenarioKey` mapping, 7 eval templates) →
**Cycle B = `srp_early_v_bb` + `srp_middle_v_bb`** (big box; same session re-dumps
BTN-vs-BB with explorer packs) → **Cycle C = `srp_sb_v_bb`**.

---

## Regenerate this snapshot

After a solve cycle, re-run and refresh the tables + Changelog:

```bash
python - <<'PY'
import json
from collections import Counter, defaultdict
d=json.load(open('assets/gto_freq_library.json')); m=d['meta']
sc=list(d['scenarios']); cells=d['scenarios'][sc[0]]['cells']; MIN=8.0
elig=[c for c in cells if c['reach_weight']>=MIN]
print('scenarios:',sc,'| streets:',m.get('streets'),'| spots:',m.get('generated_spots'))
print(f'cells {len(cells)} | eligible {len(elig)} ({100*len(elig)/len(cells):.0f}%)')
for k in ('street','position','spr_bucket','facing','hand_class'):
    print(k, dict(Counter(c[k] for c in elig)))
print('distinct textures:', len({c['texture'] for c in elig}))
PY
```

---

## Changelog

| Date | Cycle | Coverage delta |
|---|---|---|
| 2026-06-28 | v1 (flop) | BTN-vs-BB SRP, **flop only**, shallow+medium SPR; ~23/40 textures; 1,590 cells |
| 2026-06-29 | phase 2b (flop+turn) | **+ turn cells** (per-node SPR); textures → **48/48**; committed SPR on turn; 6,607 cells (6,172 eligible, 93%); eval re-baseline clean (freq-agreement 95.5→100%) |
| 2026-06-30 | deep-SPR | **+ deep regime (SPR 15 ≈ 100bb deep-cash)** for BTN-vs-BB SRP, flop+turn; cleared the 32 GB OOM on an r7a.8xlarge / 256 GB spot box (25 deep spots, `--parallel 4`, 65 min, 0 failures, all ≤0.5% expl); 9,137 cells (8,779 eligible, 96%); deep ≈ 28% of eligible. **Eval re-baseline NOT yet run** (deep cells aren't exercised by the current flop/turn benchmark — deferred with the full re-baseline) |
| 2026-07-01 | river | **+ river cells** ('river' profile / dump_rounds 3 — river check-raise faithful); full re-solve of all 78 BTN-vs-BB SRP spots (all SPR incl. deep) on a 128-vCPU / 1 TB r7a.32xlarge (us-east-1), `--parallel 5`, ~6 h, 0 failures, all ≤0.5% expl; **11,764 cells (11,400 eligible, 97%)**; river ≈ 23% of eligible. Full postflop (flop+turn+river) for BTN-vs-BB now complete. Enabled by the per-spot **subprocess tabulator** (commit 0130619) — the old Isolate.run shared-GC stalled deep river parses. **Eval re-baseline + `gen_gto_spots.dart --write` (fires the 4 river eval templates) NOT yet run — pending.** |
