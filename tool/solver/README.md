# tool/solver — TexasSolver calibration bridge (operator-only)

A local harness that maps recorded TableLab hands into [TexasSolver] postflop solves
and compares the solver's GTO output against the Decision-Context Engine heuristics
(EQR realized-equity multipliers, SPR commitment). **Not shipped, not user-facing** —
it runs locally against the licensed solver binary to *calibrate* `lib/equity/`.

> New to how a CFR solver actually works (game tree, regret matching, the dump JSON
> structure, range narrowing, how it maps to the DCE)? Read **`SOLVER_PRIMER.md`** first.

## External dependency (not in this repo)

This requires the **commercially-licensed TexasSolver CPU source**, built locally — it
is intentionally NOT committed (republishing that source would breach the license).
Point the harness at it via `TEXASSOLVER_DIR` env var or a gitignored
`tool/solver/solver_config.json`:

```json
{ "sourceDir": "C:\\path\\to\\TexasSolver\\...\\source" }
```

(the dir containing `vsbuild/console_solver.exe` and `resources/`).

### Required solver-source patches

The stock `console_solver` dump emits **strategy frequencies only — no EV**. Two local
patches to the licensed source add per-combo, per-action EV to the flop nodes of the
dump (see `memory/solver-engine-landscape` for the full rationale):

1. **`BestResponse::computeEvs`** (+ `ev_mode`) — average-strategy value walk that
   records each flop action node's per-combo, per-action **GTO EV in chips** → emitted
   as the `"ev"` field. Must null-guard `getTrainable(deal)` (pruned deals return null).
2. **`BestResponse::computePassiveEvs`** (+ `passive_mode`) — same, but hero is
   restricted to CHECK/CALL/FOLD (never bet/raise) vs the GTO opponent → **showdown
   realization with fold equity stripped** → emitted as `"ev_passive"`.
3. **`PCfrSolver::dumps`** calls both and `reConvertJson` attaches `"ev"`/`"ev_passive"`
   to flop (`deal==0`) action nodes.
4. **TLSD v1 binary dump** (full-density cost plan WS1, 2026-07-09) — a compact
   little-endian binary alternative to the JSON dump: ~10× smaller on disk,
   parseable in a fraction of the heap (the ~15 GB JSON → ~150 GB Dart heap
   parse was what capped `--parallel` at ~5 on a 1 TB box). ADDITIVE — the JSON
   path is untouched and stays the validation oracle. Touched files:
   - `src/solver/PCfrSolver.cpp` — `TlsdWriter` + `reConvertBinary` (walk twin
     of `reConvertJson`, same isomorphism-exchange semantics) + `dumps_binary`.
     The authoritative format spec is the block comment above `TlsdWriter`;
     the Dart reader (`tool/solver/dump_codec.dart`) mirrors it field by field.
   - `include/solver/PCfrSolver.h`, `include/solver/Solver.h` (non-pure virtual
     `dumps_binary`, default-throws), `include/runtime/PokerSolver.h` +
     `src/runtime/PokerSolver.cpp` (`dump_strategy_bin`),
     `src/tools/CommandLineTool.cpp` (**`dump_result_bin <path>`** command).
   Select per solve via `TLSOLVE_DUMP_FMT=json|bin|both` (`both` = one solve,
   two dumps — feeds `validate_dump.dart` and `pack_oracle.dart`).
   `--emit-pack` works on BOTH formats since the TLSD pack port (2026-08-05,
   explorer_pack walks DumpNodeView); TLSD is the pack-fleet default.

## Files

| File | Role |
|---|---|
| `solver_input.dart` | `PokerHand` → `SolverSpot` (board, IP/OOP GTO ranges via `chart_keys`/`gto_ranges`, pot, eff stack, hero contribution). Single-raised, heads-up-to-flop, flop decision only. |
| `run_solver.dart` | Writes solver input, runs `console_solver`. `solve()` parses hero combo's strategy + `ev` + `ev_passive` (flop node). `solveRoot(dumpRounds:2)` returns the whole tree + walk helpers (`followChildren`, `nodeAggregateStrategy`) for the volatility batch. |
| `poc.dart` | Proof-of-concept: one fixture + one real hand, prints solver action/EV vs DCE FACTs. |
| `batch.dart` | EQR calibration batch: balanced spots per {hand-class × position} bucket → `batch_report.md`. Resumable. |
| `volatility_batch.dart` | **Board-volatility (DCE Tier A) calibration:** stratified spots across the dynamism range; per spot reads `boardDynamism` (Phase 1) + hero turn-equity spread (`lib/equity/`) + GTO flop c-bet sizing + GTO turn-to-turn sizing dispersion (the `dumpRounds:2` turn-walk) → `volatility_report.md`. Resumable. |
| `export_one_hand.dart` | Pulls one real recorded hand → `real_hand.json` (needs `SUPABASE_*`). |

## Run

```bash
dart run tool/solver/poc.dart                       # 2-spot proof of concept
dart run tool/solver/batch.dart 6 72                # EQR batch: maxPerBucket=6, totalCap=72
dart run tool/solver/volatility_batch.dart 24       # board-volatility batch: totalCap=24
dart run tool/solver/export_one_hand.dart           # export one real hand (env creds)
```

> **Turn-node dump:** `volatility_batch.dart` solves with `set_dump_rounds 2` so the dump
> includes turn action nodes. A chance node stores its per-card children under `dealcards`
> (keyed by card string, the whole deck enumerated — skip board/hero cards), NOT `childrens`;
> action nodes use `childrens`. See `SOLVER_PRIMER.md` §6.

Solve settings are env-tunable (defaults shown):
`TLSOLVE_ACCURACY=0.5` (exploitability % stop), `TLSOLVE_MAXITER=150`,
`TLSOLVE_BETS=multi` (`single` = fast 50%+allin POC profile), `TLSOLVE_TIMEOUT_S=720`
(per-spot cap; a timed-out spot is recorded as errored, not fatal). The `multi`
profile is tiered — flop gets `33,75 + raise + allin`, turn/river a single `66 + allin`
to bound the deep-tree explosion at high SPR. A settings change invalidates the
resume cache (the config tag is in each spot's signature), so changing knobs re-solves.

## Realized-equity definitions (calibration target)

Net-chip EV frame (verified by regression `EV/pot ≈ 1.45·rawEq − 0.62`):

- **EQR_emp (total)** `= (EV_GTO + C_hero) / pot / rawEq` — includes fold equity.
- **EQR_show (no fold equity)** `= (passiveEv + C_hero) / pot / rawEq` — showdown
  realization only; the right target for the bluff-catch EQR multiplier.

`C_hero` = hero's actual committed chips (not pot/2 — dead money makes pot > 2·C_hero).

## Caveats

Deep multi-bet solves can take minutes each (per-spot timeout guards runaways). Flop
decisions only (turn/river would need tree-walking + bet-size matching). The `single` bet
profile + loose accuracy is the fast POC mode; `multi` + tight accuracy is the calibration
default. `solver_config.json`,
`real_hand.json`, `batch_results.json`, and `*.log` are gitignored. Findings:
`batch_report.md`, `POC_FINDINGS.md`, and `memory/solver-engine-landscape`.

[TexasSolver]: https://github.com/bupticybee/TexasSolver
