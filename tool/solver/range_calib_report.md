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

---
_Operator-only; `dart run tool/solver/range_calib_batch.dart`. Feeds the Phase-3 refit of `villain_range.dart` narrowing params (branch → PR → re-eval)._
