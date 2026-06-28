// DCE Q2 — Phase 1 instrumentation. Reconstruct the solver's reach-weighted
// VILLAIN range at a node (each combo weighted by its GTO strategy frequency for
// the action taken) and compute hero's pot equity vs it — the GTO ground truth we
// calibrate `lib/equity/villain_range.dart`'s heuristic range narrowing against.
// The same dump also yields hero's GTO action frequencies (substrate for the
// future Q1 frequency library). Operator-only; runs against the licensed solver.
//
// Dump shape (see SOLVER_PRIMER §6): an action_node has
//   strategy.actions: ["CHECK","BET 6.6", …]
//   strategy.strategy: { "AcJh": [f_check, f_bet, …], … }  // per-combo freqs
// so villain's range that takes action i = { combo : freq[i] }, reach-weighted.

import 'dart:math';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/evaluator.dart';

typedef WeightedCombo = ({List<int> cards, double w});

/// Parse a dump strategy key ("AcJh" / "Ac Jh") to two card ints, or null.
List<int>? parseComboKey(String key) {
  final k = key.replaceAll(' ', '');
  if (k.length < 4) return null;
  final a = parseCard(k.substring(0, 2)), b = parseCard(k.substring(2, 4));
  return (a < 0 || b < 0) ? null : [a, b];
}

/// Action labels at an action [node].
List<String> nodeActions(Map<String, dynamic> node) =>
    ((node['strategy'] as Map<String, dynamic>?)?['actions'] as List?)
        ?.cast<String>() ??
    const <String>[];

/// The acting player's reach-weighted range that takes action [actionIdx] at
/// [node]: each combo weighted by its GTO frequency for that action (0-freq
/// combos drop). [node] must be an action_node.
List<WeightedCombo> nodeActionRange(Map<String, dynamic> node, int actionIdx) {
  final byCombo = (node['strategy'] as Map<String, dynamic>?)?['strategy']
      as Map<String, dynamic>?;
  final out = <WeightedCombo>[];
  byCombo?.forEach((key, v) {
    if (v is! List || actionIdx >= v.length) return;
    final w = (v[actionIdx] as num).toDouble();
    if (w <= 1e-9) return;
    final cards = parseComboKey(key);
    if (cards != null) out.add((cards: cards, w: w));
  });
  return out;
}

/// The acting player's FULL range at [node] (every combo, weight 1) — the
/// un-narrowed baseline.
List<WeightedCombo> nodeFullRange(Map<String, dynamic> node) {
  final byCombo = (node['strategy'] as Map<String, dynamic>?)?['strategy']
      as Map<String, dynamic>?;
  final out = <WeightedCombo>[];
  byCombo?.keys.forEach((key) {
    final cards = parseComboKey(key);
    if (cards != null) out.add((cards: cards, w: 1.0));
  });
  return out;
}

/// Hero's pot equity (0–1) vs a WEIGHTED villain range on [board], by weighted
/// Monte Carlo (sample a villain combo ∝ weight, deal the runout, evaluate).
/// NaN when no villain combo survives card removal. Reuses the 7-card evaluator.
double heroEquityVsWeightedRange(
  List<int> hero,
  List<int> board,
  List<WeightedCombo> villain, {
  int iterations = 20000,
  int seed = 7,
}) {
  final rng = Random(seed);
  final dead0 = <int>{...hero, ...board};
  final combos = <List<int>>[];
  final cum = <double>[];
  var total = 0.0;
  for (final v in villain) {
    if (v.cards.any(dead0.contains)) continue; // conflicts with hero/board
    total += v.w;
    combos.add(v.cards);
    cum.add(total);
  }
  if (combos.isEmpty || total <= 0) return double.nan;
  final need = 5 - board.length; // runout cards to deal (flop→2, turn→1, river→0)

  var score = 0.0, n = 0;
  for (var it = 0; it < iterations; it++) {
    // Sample a villain combo proportional to weight (binary search the CDF).
    final r = rng.nextDouble() * total;
    var lo = 0, hi = cum.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] < r) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final vc = combos[lo];
    final dead = <int>{...dead0, ...vc};
    final runout = <int>[];
    while (runout.length < need) {
      final c = rng.nextInt(52);
      if (dead.add(c)) runout.add(c);
    }
    final hv = evaluateBest([...hero, ...board, ...runout]);
    final vv = evaluateBest([...vc, ...board, ...runout]);
    if (hv > vv) {
      score += 1;
    } else if (hv == vv) {
      score += 0.5;
    }
    n++;
  }
  return n == 0 ? double.nan : score / n;
}
