# Range Migration Plan — PokerCoaching charts as canonical preflop ranges

**Decision (2026-08-19, owner):** replace the hand-authored binary presets in
`lib/equity/gto_ranges.dart` with PokerCoaching.com's solver-derived,
mixed-frequency charts as the canonical preflop ranges for ALL tree building
going forward. **8-max is the canonical format.** Licensing: owner's decision —
these are free PokerCoaching resources (free chart PDFs + free-account site
charts); no license sought. PeakGTO uses the same ranges for its sims.

## Why (audit findings, 2026-08-19 session)

The current 51 hand-authored charts have systematic defects:
- **Seam bugs**: call charts stop at 88, 3-bet charts start at JJ → 99/TT (and
  JJ vs UTG) fold; broadway seam drops KJs/KTs/KQo/AJo. Monotonicity
  violations in nearly every defense chart (BB vs SB is the only clean one).
- **~Half-of-equilibrium defense width** (BB vs BTN defends 30% vs ~55-60%).
- **9-max ladder mislabeled into the 6-max Explorer trail**: `srp_early_v_bb`
  was solved with the 5.9% nine-max UTG chart while the UI presents 6-max.
- **One range reused at all SPR regimes** (shallow trees use 100bb ranges).
- No SB limp, no squeeze, no 4-bet/5-bet pots, no depth ladder, no mixing.

Full audit detail: memory `range-audit-findings` + session logs 2026-08-19.

## Sources (all inventoried 2026-08-19)

1. `C:\Users\rhtk1\Downloads\The Ultimate Cash Game Preflop Guide.pdf` — 2026,
   8-max (UTG, UTG+1, LJ, HJ, CO, BTN, SB, BB), ~200 charts: RFI / vs-RFI
   (incl. BB vs SB-limp) / vs-3-bet / vs-4-bet / vs-5-bet/6-bet, at 100BB AND
   200BB.
2. `C:\Users\rhtk1\Downloads\The_Ultimate_Tournament_Preflop_Guide.pdf` — 2026,
   8-max, ~500 charts: same layers at 80/50/30/20/12BB with All-In variants at
   ≤30BB.
3. **https://pokercoaching.com/gto-charts/ (login required — the superset and
   the EXTRACTION SOURCE)**: Tournament 8-max at a 2-100bb ladder (~14 active
   depths: 2,3,4,5,6,7,8,9,10,12,15,20,25,30,40,50,60,80,100; 17/35 greyed),
   Cash 8-max 100/200bb, Cash 6-max 100bb, HU MTT, HU Cash. Actions: RFI,
   vs RFI, vs 3-Bet, vs 4-Bet, **vs Raise-Call** (squeeze node with raiser-seat
   × caller-seat selectors; 8-max only), All-In 4bet, All-In 5bet (MTT).
   Charts are MIXED-FREQUENCY. Push/Fold section covers ≤~10bb separately.

**Extraction — DONE 2026-08-19 (far better than scraping).** The page loads
its ENTIRE dataset from `GET /api/get-training-weights?gameFormat={MTT|Cash}`
(auth cookies; fetched in-page via the user's logged-in Chrome, transferred
out via a one-shot localhost bridge — `ranges_pc/receive.py`). Raw payloads
committed as `tool/solver/ranges_pc/raw/pc-{mtt,cash}.json.gz` (uncompressed
`.json` gitignored; `gunzip -k` to regenerate).

**Dataset:** 2,429 ranges. Cash 569 (8Max 323 · 6Max 235 · HU 11; 100/200bb;
squeeze charts: 112 8Max + 28 6Max). MTT 1,860 (8Max 1,734 · HU 126; bbs
2,3,…,100 including 17 & 35 the UI greys out).

**Schema (`ranges[]`):** `format` (MTT/Cash) · `type` (8Max/6Max/HU) · `seat`
· `bbs` · `handed` · `villains`/`villainSeat`/`villainSeat2` · **`action` =
the situation hero FACES**: `Folded To` (=RFI spot), `Open Raise` (=vs RFI),
`3bet`, `4bet`, `Squeeze` (=vs raise+call), `Limp` (=vs limp), `All-In
3bet/4bet/5bet` · `heroBetSize`/`raiseSize` (bb) · `sequence`/`simpleSequence`
(preflop line, e.g. `F-F-F-F-F-R-F`) · `ante` · sometimes `excludeHands` ·
`handsWeights`: hand → `["f: x","c: x","r (size): x", …]` frequencies
summing to 1, with raise-TO sizes embedded in the labels.

**Validation (2026-08-19):** Cash 8Max 100bb BTN `Folded To` = 40.3% open @
3bb ✓ (expected 40-44). BB vs BTN open = call 25.5 / 3-bet 12.7 / fold 61.8 —
and every hand the audit flagged now defends: TT 3-bets 100%, 99 c64/r36,
KJs c46/r54, KTs c14/r86, KQo c31/r69, AJo c47/r53, K9s c71/r29.

**Sizing note for Phase B:** PC trees use THEIR sizes (BTN open 3bb — not our
current 2.5x; BB 3-bet to 12bb; all-in nodes explicit). Adopt PC sizes when
re-solving so ranges and tree geometry stay consistent; `heroBetSize`/
`raiseSize` carry them per chart.

## Phase A — ingestion & plumbing (no solver cost)

1. **Extractor** (`tool/solver/extract_pc_charts.*` — browser-driven): scrape
   Cash 8-max (both depths, all actions incl. raise-call) + MTT 8-max at the
   depths our regimes need first (100/50/30/20/12), then the rest of the
   ladder + 6-max cash + HU as archive. Validate: every cell's action freqs
   sum to 100%; spot-check vs the PDFs.
2. **Weighted range format**: `GtoPreset` v2 (hand → {action: freq}) or a
   parallel weighted store; binary views derived via threshold for consumers
   that need in/out (quick-hand synthesis classifier).
3. **Key remap**: `chart_keys.dart` moves from early/middle/late buckets to
   real position pairs (8-max). Explorer trail seats remapped/relabeled —
   fixes the 6-max/9-max mismatch (decide: render 8-max trail, or map 6-max
   display seats onto 8-max charts LJ→BB).
4. **Consumers**: `freq_grid.dart` scenario ranges (TexasSolver accepts
   weighted `AA:0.5` notation); `villain_range.dart` (weighted combo
   sampling); `preflop_ranges.dart` (true mixed-frequency strip display);
   equity-calculator presets; `quick_hand_synthesis.dart` (threshold);
   eval fixtures re-bake.
5. SB limp + raise-call charts wired into the preflop layer (trail, synthesis,
   villain model). NOT solvable postflop (multiway; TexasSolver is HU).

## Phase B — re-solve the current 5 scenarios (~$1.5-1.9k, one fleet cycle)

Same 26,325 spots (5 scenarios × 1,755 flops × 3 SPR), new ranges, and
**depth-appropriate ranges per regime** (shallow uses MTT ~30bb charts or cash
short — decide per scenario; medium 100bb; deep 100/200bb). Existing runbook
(`VCPU_RUNBOOK.md`, golden AMI, `vcpu-solve.ps1`); budget +35% egress lesson;
ends with full eval re-baseline on the SEPARATE Anthropic key. Explorer packs
re-emitted (`--emit-pack`), R2 catalog swap. Bundle with the sizing-strategy
cycle if timing aligns.

## Phase C — expansion unlocked (each HU scenario: 5,265 spots full-density
≈ $300-380, or 234 library-only ≈ $20-40)

Priority order: (1) more 3-bet pots (have 1 of ~22 pairs — SB vs BTN, CO vs
UTG first); (2) 4-bet pots (new type, cheap low-SPR trees); (3) 200bb cash
regime; (4) limped BvB pot; (5) more SRP pairs (SB defend vs BTN, BTN vs CO
cold-call); (6) HU formats. Squeeze/raise-call = preflop layer only.

## Open decisions / risks

- Explorer trail presentation: full 8-max seats vs 6-max subset of 8-max
  charts (leaning full 8-max — matches live full-ring audience).
- MTT vs cash range split for the shallow regime (may fork scenario families).
- Eval gates (98/90/95) must re-baseline after ANY prompt/FACT-input change —
  the GTO-frequency FACT's library changes wholesale here.
- Extraction fidelity: gradient-split → frequency parsing must be validated
  against PDF charts before anything downstream consumes it.
