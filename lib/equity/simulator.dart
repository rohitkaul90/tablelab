import 'dart:math';
import 'package:flutter/foundation.dart';
import 'evaluator.dart';

class SimulationResult {
  final List<double> equity; // per player, sums to 1.0
  final List<int> wins;
  final List<int> scoops; // wins without any ties
  final int iterations;

  const SimulationResult({
    required this.equity,
    required this.wins,
    required this.scoops,
    required this.iterations,
  });
}

// Params sent to isolate — must be plain Dart (no Flutter objects)
class _SimParams {
  final List<List<List<int>>> ranges; // [player][combo][0 or 1]
  final List<int> boardCards; // 0-5 known board cards
  final int iterations;

  const _SimParams({
    required this.ranges,
    required this.boardCards,
    required this.iterations,
  });
}

Future<SimulationResult> runSimulation({
  required List<List<List<int>>> ranges,
  required List<int> boardCards,
  int iterations = 50000,
}) {
  final params = _SimParams(
    ranges: ranges,
    boardCards: boardCards,
    iterations: iterations,
  );
  return compute(_isolatedSim, params);
}

/// Synchronous core, for callers that are ALREADY inside an isolate (e.g. the
/// equity cross-check, which runs its whole street walk off the main thread)
/// and must not nest a `compute()`. On the main thread use [runSimulation].
SimulationResult runSimulationSync({
  required List<List<List<int>>> ranges,
  required List<int> boardCards,
  int iterations = 50000,
}) =>
    _isolatedSim(_SimParams(
      ranges: ranges,
      boardCards: boardCards,
      iterations: iterations,
    ));

// Top-level function for compute()
SimulationResult _isolatedSim(_SimParams p) {
  final n = p.ranges.length;
  final wins = List.filled(n, 0);
  final scoops = List.filled(n, 0);
  final equitySum = List.filled(n, 0.0);
  int validIter = 0;

  final rng = Random();

  for (int iter = 0; iter < p.iterations; iter++) {
    final used = <int>{...p.boardCards};
    final hands = <(int, int)>[];
    bool ok = true;

    // Deal random hand to each player from their range
    for (int pl = 0; pl < n; pl++) {
      final avail = p.ranges[pl]
          .where((c) => !used.contains(c[0]) && !used.contains(c[1]))
          .toList();
      if (avail.isEmpty) {
        ok = false;
        break;
      }
      final combo = avail[rng.nextInt(avail.length)];
      hands.add((combo[0], combo[1]));
      used.add(combo[0]);
      used.add(combo[1]);
    }
    if (!ok) continue;

    // Complete board to 5 cards
    final deck = [for (int i = 0; i < 52; i++) if (!used.contains(i)) i];
    for (int i = deck.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = deck[i];
      deck[i] = deck[j];
      deck[j] = tmp;
    }
    final board = [...p.boardCards];
    int di = 0;
    while (board.length < 5) { board.add(deck[di++]); }

    // Evaluate each player's best 7-card hand
    final strengths = [
      for (int pl = 0; pl < n; pl++)
        evaluate7([hands[pl].$1, hands[pl].$2, ...board])
    ];

    final best = strengths.reduce(max);
    final winners = [for (int pl = 0; pl < n; pl++) if (strengths[pl] == best) pl];

    validIter++;
    final share = 1.0 / winners.length;
    for (final pl in winners) {
      wins[pl]++;
      equitySum[pl] += share;
      if (winners.length == 1) scoops[pl]++;
    }
  }

  final equity = validIter > 0
      ? [for (int pl = 0; pl < n; pl++) equitySum[pl] / validIter]
      : List.filled(n, 1.0 / n);

  return SimulationResult(
    equity: equity,
    wins: wins,
    scoops: scoops,
    iterations: validIter,
  );
}
