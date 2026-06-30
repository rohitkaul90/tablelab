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

## Snapshot — as of 2026-06-30 (deep-SPR added)

`scenario = srp_late_v_bb` (BTN open vs BB call, heads-up, single-raised) — **the only
scenario**. `9,137` cells total, `8,779` **serve-eligible** (clear lookup `minMass=8`) = **96%**.

| Attribute | Covered | Distribution (serve-eligible) | Gap |
|---|---|---|---|
| **Street** | flop + turn | turn 70% / flop 30% | **river 0%** |
| **Position** | IP + OOP | ~50% / ~50% | none (HU complete) |
| **SPR bucket** | shallow (~25bb) + medium (~40bb) + **deep (~100bb)**; committed appears on turn (post bet-call) | deep 28% / medium 28% / shallow 28% / committed 16% | none across the SRP band (deep added 2026-06-30) |
| **Texture** | all **48/48** cells (3 suit × 2 pairing × 4 high-card × 2 connectedness) | fully spanned | none (flop+turn together cover the whole space) |
| **Facing node** | all 6: first_to_act, facing_check, facing_bet_{small,mid,big}, facing_raise | big 26 / raise 21 / mid 18 / check 13 / fta 13 / small 10 | per-street size seam (below); `facing_allin` = 0 cells |
| **Hand class** | all 5: air, weakDraw, strongDraw, marginalMade, strongMade | 13–23% each (balanced) | none |

**Per-street facing seam:** the solve bets flop 33/75 (→ small/big) and turn 66 (→ mid),
so per-street the native faced-bet sizes are coarse; raises + the cross-street merge fill
the rest. All 6 buckets exist in aggregate.

**`facing_allin` mismatch (latent):** the tabulator labels an all-in `facing_allin` but
the live lookup queries `facing_bet_*`/`facing_raise` — currently **0** such cells exist
(low reach → suppressed), so no live impact today; fix the label before the next solve so
future shove cells are reachable.

---

## Structural gaps — the real roadmap (ranked by size)

The snapshot above is **one slice** of the intended product surface. As a fraction of the
full surface (≈8 scenarios × 3 streets × 4 SPR regimes × HU/multiway × chip-EV/ICM), this
is a **~low-single-digit-to-15% slice — but the single highest-frequency one** (BTN-vs-BB
SRP is the most common HU postflop spot).

1. **Scenario ≈ 1 of ~8** — only BTN-vs-BB single-raised. **Zero** for 3-bet/4-bet pots,
   other openers (UTG/CO/SB), blind-vs-blind, limped pots. *Biggest gap.*
2. **River = 0%** — next solve; heaviest tree (dump_rounds 3).
3. **Multiway = 0%** — HU only. Multiway is handled *directionally* by the MDF FACT, no freqs.
4. ~~**Deep cash (100bb, SPR ~15–17) = 0%**~~ — ✅ **covered 2026-06-30** (deep SPR 15
   added for BTN-vs-BB SRP, flop+turn; solved on an r7a.8xlarge / 256 GB spot box, which
   cleared the 32 GB OOM that blocked it locally). Remaining deep gap: **river** at deep
   SPR, and deep for any non-BTN-vs-BB scenario.
5. **Game type: chip-EV only, no ICM.** No cash/tournament axis. Most applicable to
   tournaments + short cash; ICM spots (bubble, FT, pay jumps) **not modeled**.

---

## Roadmap & compute (next solve cycles)

Real per-spot timings this run (8 threads, local): shallow ~250–490s, medium ~750–1,430s,
**~700s avg**. The grid is *embarrassingly parallel* (independent spots).

| Milestone | Spots | Local (serial-ish) | 96-vCPU Linux (12 parallel × 8t) | Needs |
|---|---|---|---|---|
| ✅ flop+turn, BTN-vs-BB (shallow+medium) | 52 | ~several h | ~50 min | — |
| ✅ + deep SPR (same scenario, flop+turn) | 26 | **blocked (OOM @32 GB)** | **65 min @ r7a.8xlarge / 256 GB, --parallel 4** | **big RAM ✓** |
| + River (same scenario) | ~26–78 | many h (deepest tree) | ~1–2 h | **big RAM** |
| + each new scenario | ~78 each | ~10+ CPU-h each | ~50 min each | — |
| + ICM | — | — | feasible | — |

**The lever:** a 64–192 vCPU, 256–512 GB Linux box → ~8–24× throughput + unblocks
deep-cash/river. The full river + multi-scenario + deep-cash roadmap drops from ~80–100
local CPU-hours (deep-cash *impossible* locally) to single-digit hours / ~$20–60 of spot
compute. License-clean — the CPU source builds on Linux (GCC flags, vendored deps; pass
`-DCMAKE_POLICY_VERSION_MINIMUM=3.5`). No pruning, no engine change.

**Bundle the next solve cycle:** river + facing_allin relabel + asymmetric-SPR handling +
turn-decision eval-coverage spots + deep-SPR — all gated on the same big-RAM Linux box.

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
