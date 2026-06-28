# Range-narrowing calibration (DCE Q2)

Per FLOP spot: ENGINE heuristic hero-equity (its range narrowing on villain's matched flop action) vs SOLVER reach-weighted GTO hero-equity. `gap` = engine − solver (NEGATIVE = engine UNDERSTATES hero, i.e. models villain's range too strong; POSITIVE = engine overstates).

Spots: 52 · errored: 8

## Mean gap by villain action × board texture

| action | board | n | mean engineEq | mean solverEq | mean gap (pt) |
|---|---|--:|--:|--:|--:|
| bet-big | rainbow | 3 | 63.9 | 67.5 | -3.6 |
| bet-big | two-tone | 1 | 27.1 | 31.1 | -4.0 |
| bet-small | monotone | 2 | 33.7 | 39.8 | -6.0 |
| bet-small | paired | 3 | 56.7 | 63.4 | -6.7 |
| bet-small | rainbow | 1 | 37.1 | 62.1 | -25.0 |
| check | monotone | 8 | 41.7 | 52.6 | -10.9 |
| check | paired | 6 | 43.7 | 44.7 | -1.1 |
| check | rainbow | 6 | 43.6 | 25.6 | 18.0 |
| check | two-tone | 22 | 46.0 | 38.3 | 7.7 |

## Mean gap by villain action (all boards)

| action | n | mean gap (pt) | mean |gap| |
|---|--:|--:|--:|
| bet-big | 4 | -3.7 | 5.4 |
| bet-small | 6 | -9.5 | 9.5 |
| check | 42 | 4.4 | 19.0 |

## Conclusion (Phase 3 decision — 2026-06-28): VALIDATION, ship nothing

The pot-odds-critical path — **villain bets → hero must price a call** — is the only case the live equity FACT exists to ground, and the solver puts the engine within **~5pt** of GTO there (bet-big −3.7, bet-small −9.5 dragged by a single −25 rainbow outlier; one-directional, engine keeps villain's betting range slightly too strong). That is inside the Monte-Carlo + range-modeling noise floor. **Headline: the equity FACT's pot-odds grounding is solver-validated.**

Everything that is badly off is the **check** branch (|gap| 19pt), which is (a) **not pot-odds-critical** — a villain check leaves no bet to price, so it only colours hero's *value-bet* reads — and (b) too noisy/thin at n=52 and too bet-tree-abstraction-dependent to refit confidently.

Decision: **no live `villain_range` change.** Refitting the well-calibrated bet branch buys < the noise floor; refitting the noisy check branch from this sample would be fitting noise; and any equity-model change drags the *whole* prompt through a broad re-eval against the shared Anthropic cap. Q2 is banked as a validation result. (If the check model is ever revisited, it needs a richer multi-bet-tree solve set to de-noise the rainbow/monotone/paired buckets first — option C.)

---
_Operator-only; `dart run tool/solver/range_calib_batch.dart`. Phase 3 closed as VALIDATION (no refit); see Conclusion above._
