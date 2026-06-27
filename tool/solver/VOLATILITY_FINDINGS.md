# Board-volatility calibration — findings (DCE Tier A)

Analysis of the 30-spot `volatility_batch.dart` run (heads-up single-raised flop,
`vol` profile, tight-converged median expl ~0.45%, 0 errored). Source numbers:
`volatility_report.md` (auto-generated) + threshold re-splits off
`volatility_results.json`. Feeds the Phase-3 wiring of `boardDynamism` into the
`analyze-hand` FACT. Mirrors `POC_FINDINGS.md` / `batch_report.md` for EQR.

## 1. The sizing prescription is real and theory-consistent ✓

GTO flop c-bet **size by hand class**, static (dynFrac < 0.50) vs dynamic (≥ 0.50):

| hand class | static size | dynamic size | shift | reading |
|---|--:|--:|--:|---|
| strongMade | 49% | **63%** | +14 | size UP for protection |
| strongDraw | 48% | **63%** | +15 | size UP, semi-bluff |
| weakDraw | 46% | 59% | +13 | size up |
| air | 51% | 56% | +5 | small/medium |
| marginalMade | 52% | **49%** | −3 | stays small — POT CONTROL |

The prescription is clean and conditioned on hero's class: **on a dynamic board,
strong made hands and strong draws size up (~60–63%) while one-pair hands pot-control
(~50%); static boards play small and uniform (~46–52%).** This is exactly the
hand-class-conditioned design — the range AGGREGATE reads backwards (GTO range-bets
dry boards at high freq), so the per-class split is what matters.

Frequency: on dynamic boards every class bets often (84–95%); static is lower/varied.
The frequency signal is noisier than the sizing signal — lead with sizing.

## 2. The board-dynamism COUNT metric SATURATES ⚠ (the load-bearing limitation)

The `boardDynamism` dynamic-fraction does NOT discriminate in the moderate→high range.
Distribution across the 30 spots:

```
0.10, 0.10, 0.33, 0.43, 0.43, 0.51, 0.57, 0.59, 0.59,
0.63×3, 0.67×4, 0.69×4, 0.76×10
```

**A third of the spots are pinned at exactly 0.76; 18/30 are ≥ 0.67.** The straight-
completing-turn count dominates (most boards allow many straight-advancing turns), so
any two-tone/connected board clips near the top. The metric only cleanly isolates
**truly dry** boards (paired/disconnected, ~0.10) from everything else.

Consequence: a binary static/dynamic label fires "dynamic" on ~80% of real boards. The
sizing regime actually transitions at **dynFrac ≈ 0.50** (below it sizes ~49–52%, above
it strong hands jump to ~60–63%); as the threshold rises to 0.60–0.67 the static group
absorbs semi-wet boards and the contrast washes out. So:

- **Recalibrate `kBoardDynamicThreshold` 0.30 → ~0.50** (the sizing-regime boundary).
- Above ~0.65 the metric is flat — it cannot rank "wet" vs "very wet". Fine for a binary
  dry/wet prescription; a poor *continuous* volatility score.

## 3. Hero equity-range across turns discriminates better

The hero-equity spread across the 47 turns (pure `lib/equity/`, no solver) tracks
volatility with a real gradient where the count saturates — report tertiles 46 / 48 /
59 pts, per-spot range 23–86 pts. It is also hero-specific (how much HERO's situation
swings), which is more decision-relevant than a board-only card count. Candidate as the
*discriminating* signal if the binary count proves too coarse in practice — but it needs
47 per-street sims at FACT time (the trust-pack equity check already sims per street, so
feasible, but a perf cost).

## Caveats (read before refitting)

1. **Corpus skews wet** — only 5/30 boards below dynFrac 0.50, so the STATIC baseline is
   thin (strongMade static = 49% rests on 5 spots / 397 combos). Directionally solid, not
   precise. More dry/paired boards would firm it (the Pluribus 6-max corpus is
   suited/connected-heavy; few dry flops survive the single-raised-HU mapping).
2. **Abstraction**: single-raised HU, flop decision only, `vol` bet tree (flop 33/75,
   turn 50/100, river 75, NO raise/allin). The sizing %s live inside that tree — read them
   as "bigger / smaller / pot-control", not exact targets.
3. The sizing %s are GTO range-aggregate per class; the FACT must be a HEURISTIC
   (directional), never a precise "bet 63%".
4. The metric saturation means the board-count FACT is best framed as **dry vs
   not-dry** + the per-class sizing lean, not a fine-grained volatility number.

## Phase-3 takeaways

- Threshold → ~0.50. Ship the per-class sizing prescription (strong hands/draws size up,
  one-pair pot-controls, static = small/uniform), conditioned on hero hand class.
- Frame the board-count FACT as dry-vs-wet (its real discriminating power) + the sizing
  lean; do NOT present the dynamic-fraction as a precise volatility score.
- Open decision: whether to add hero equity-range-across-turns as the discriminating
  signal (better, hero-specific, costs per-street sims) or ship the cheap board-count
  binary now and revisit. See memory/decision-context-engine.
