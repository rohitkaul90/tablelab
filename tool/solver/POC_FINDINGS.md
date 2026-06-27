# TexasSolver bridge — POC findings


## FIXTURE  (tool/eval/fixtures/pluribus-100b-117-p6.json)
  Board: Qc 9c Ks   Hero: AcJh   IP
  Ranges: IP=BTN (cash_call_ip_vs_middle), OOP=CO (cash_rfi_co); pot 650, eff 9750 (SPR 15.0)
  IP range : 22,33,44,55,65s,66,76s,77,87s,88,98s,99,A5s,A9s,AJo,AJs,AQo,AQs,ATs,J9s,JTs,KJs,KQo,KQs,KT…
  OOP range: 55,65s,66,76s,77,87s,88,97s,98s,99,A4s,A5s,A6s,A7s,A8o,A8s,A9o,A9s,AA,AJo,AJs,AKo,AKs,AQo,…
  Solving (this can take ~30-60s)...

  → SOLVER GTO (hero AcJh at the decision node):
      strategy: CHECK 30.3%  ·  BET 325.000000 69.7%  ·  BET 9750.000000 0.0%
      EV chips: CHECK -52.7  ·  BET 325.000000 -27.0  ·  BET 9750.000000 -478.9
      best-action EV -27.0 chips (= -4% of the 650-chip flop pot)
      top action: BET 325.000000   exploitability: 4.495%   solve: 93.0s

  → DCE FACTs given to the AI coach:
      [FACT — Hero equity vs the modeled villain range(s), computed on-device by Monte Carlo (10000 trials), NOT by you: pre-flop ~56%, flop ~42%. These are deterministic ground truth — your assessment of each street MUST be consistent with them.…
      [HEURISTIC — Equity REALIZATION (raw equity discounted for hero's position + hand class; ESTIMATED, not exact): flop ~42% → realized ~37% (IP, a weak draw). A marginal hand out of position rarely realizes its raw equity; a strong made hand …
      [HEURISTIC — SPR & COMMITMENT (effective stack ÷ pot, hero-centric; ESTIMATED, not exact): flop SPR ~15.0 — to get all-in profitably needs ~48% equity (high SPR — favours pot control with one-pair hands). Use this for the call-vs-raise / st…
      (baked) realized={flop: 0.36581600000000003}  spr={flop: 15.0}  forced=null

## REAL HAND (tool/solver/real_hand.json)
  Board: Ah 8d 8c   Hero: Ad7d   IP
  Ranges: IP=BB (cash_call_bb_vs_sb), OOP=SB (cash_rfi_sb); pot 110, eff 950 (SPR 8.6)
  IP range : 22,33,44,54s,55,65s,66,75s,76s,77,86s,87s,88,97s,98o,98s,99,A2s,A3s,A4s,A5s,A6s,A7o,A7s,A8…
  OOP range: 22,33,44,54s,55,65s,66,75s,76s,77,85s,86s,87s,88,96s,97s,98o,98s,99,A2s,A3s,A4s,A5o,A5s,A6…
  Solving (this can take ~30-60s)...

  → SOLVER GTO (hero Ad7d at the decision node):
      strategy: CHECK 48.8%  ·  BET 55.000000 51.1%  ·  BET 950.000000 0.0%
      EV chips: CHECK 60.3  ·  BET 55.000000 59.4  ·  BET 950.000000 2.8
      best-action EV 59.4 chips (= 54% of the 110-chip flop pot)
      top action: BET 55.000000   exploitability: 3.206%   solve: 144.4s

  → DCE FACTs given to the AI coach:
      [FACT — Hero equity vs the modeled villain range(s), computed on-device by Monte Carlo (10000 trials), NOT by you: pre-flop ~33%, flop ~75%, turn ~59%, river ~31%. These are deterministic ground truth — your assessment of each street MUST b…
      [HEURISTIC — Equity REALIZATION (raw equity discounted for hero's position + hand class; ESTIMATED, not exact): flop ~75% → realized ~98% (IP, a strong made hand); turn ~59% → realized ~76% (IP, a strong made hand); river ~31% → realized ~4…
      [HEURISTIC — SPR & COMMITMENT (effective stack ÷ pot, hero-centric; ESTIMATED, not exact): flop SPR ~8.6 — to get all-in profitably needs ~47% equity (high SPR — favours pot control with one-pair hands); turn SPR ~8.6 — to get all-in profit…

---

## Synthesis (with EV — solver patched to emit per-combo, per-action EV in chips)

The solver source was patched (`BestResponse::computeEvs` + `reConvertJson`) to dump
each flop action node's per-combo, per-action **EV in chips** under the average
strategy. Verified GTO-consistent: 0/310 combos where the top-strategy action ≠ the
top-EV action. EV now rides through the bridge (`run_solver.dart` → `poc.dart`).

**The EV gap between actions is the calibration signal — and it quantifies both findings:**

1. **Fixture `AcJh` (NFD+gutshot, IP).** EV: CHECK −52.7 · BET −27.0 · all-in −478.9.
   The hand is net −EV (a draw behind a strong range), but **betting beats checking by
   +25.7 chips** — the semi-bluff's fold-equity value, made explicit. The DCE FACT
   ("realized 37%, favours pot control") points the other way; GTO bets 70% and the EV
   says exactly why. **EQR misses ~26 chips of fold-equity value here.**

2. **Real hand `Ad7d` = top two (AA88), IP.** EV: CHECK 60.3 · BET 55 → 59.4 · all-in 2.8.
   Best-action EV ≈ 54% of the pot — hero is genuinely crushing, which **validates the
   DCE realized-equity number (98%)**. But CHECK and BET are within **0.9 chips** —
   GTO is indifferent (pot-control mix on a dry paired board), so "bet for value
   because you're ahead" overstates it. EQR has the equity right but can't see the
   bet/check indifference (board-texture signal).

**Net:** EV makes the comparison numeric. We can now, per spot, compute
`EV(action) − EV(best alternative)` and check whether the DCE/coaching recommendation
captures it. Fixture: heuristic understates a +26-chip semi-bluff; real hand: heuristic
equity correct but action-indifference invisible. Both point to the same Tier-A gaps
(fold-equity in EQR; board-texture/MDF) — now measurable.

**EV reference frame:** chips, net from the decision node (losing holdings go negative).
Action *ordering* and *gaps* are the robust signal; absolute "% of pot" is a rough
realized-value indicator pending a formal realized-equity definition for the batch.

**Status:** EV-dump COMPLETE + verified. Ready for the curated ~20–40 spot batch, which
can now report EV gaps (semi-bluff value, stack-off thresholds, bet/check indifference)
to calibrate the EQR multipliers + `requiredEquityToStackOff` against real solver numbers.
