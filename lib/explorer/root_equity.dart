// GTO Explorer — on-device equity for the player who has NO stored equity at a
// street's root.
//
// Packs store per-combo equity only for the ACTING player at each node, so at a
// street's very first decision the OTHER player's distribution has no stored
// source:
//   • Flop root — the opponent's range is their full entering range; sampled
//     UNIFORMLY (nothing has narrowed yet).
//   • Turn/River root — the opponent arrives having bet/called earlier, so
//     their range is reach-SKEWED; we sample it WEIGHTED by each combo's reach
//     and evaluate on the current (turn/river) board.
// Both run inside compute() and evaluate hero-vs-range all-in equity with the
// shared evaluator + a seeded PRNG (deterministic per spot).

import 'dart:math';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/evaluator.dart';

import 'pack_codec.dart';

/// Flop-root payload: the not-yet-acted player's range vs the actor's range,
/// both sampled uniformly (no postflop narrowing has happened at the root).
class RootEquityPayload {
  final List<String> heroCombos; // the not-yet-acted player's combo names
  final List<String> villainCombos; // the acted player's combo names
  final List<int> board; // card ints (3 for the flop root)
  final int iterations; // per combo
  final int seed;
  RootEquityPayload({
    required this.heroCombos,
    required this.villainCombos,
    required this.board,
    this.iterations = 200,
    this.seed = 1234,
  });
}

/// A combo with a reach weight: reach drives the curve's x-axis (for the hero)
/// and the weighted sampling probability (for the villain range being faced).
class WeightedCombo {
  final int comboId; // index into the hero position's manifest combo list
  final String name; // 'AhKs'
  final double reach;
  const WeightedCombo(this.comboId, this.name, this.reach);
}

/// Turn/River-root payload: a reach-WEIGHTED opponent range ([hero], whose
/// curve we want) vs the actor's reach-weighted range ([villain], the range it
/// faces) on the current board.
class OppRangeEquityPayload {
  final List<WeightedCombo> hero;
  final List<WeightedCombo> villain;
  final List<int> board; // 4 (turn) or 5 (river) cards
  final int iterations;
  final int seed;
  OppRangeEquityPayload({
    required this.hero,
    required this.villain,
    required this.board,
    this.iterations = 200,
    this.seed = 1234,
  });
}

/// Flop root: equity of every hero combo vs the villain range (uniform reach)
/// on the board, as synthetic [PackCombo]s (reach 1.0). Top-level so compute()
/// can run it.
List<PackCombo> computeRootEquities(RootEquityPayload p) => _mcRangeEquities(
      hero: [
        for (var i = 0; i < p.heroCombos.length; i++)
          WeightedCombo(i, p.heroCombos[i], 1.0)
      ],
      villain: [for (final n in p.villainCombos) WeightedCombo(0, n, 1.0)],
      board: p.board,
      iterations: p.iterations,
      seed: p.seed,
    );

/// Turn/River root: equity of every hero (opponent) combo vs the actor's
/// reach-weighted range on the current board. Each output [PackCombo] carries
/// the hero's reach (so the curve's x-axis stays reach-weighted).
List<PackCombo> computeOppRangeEquities(OppRangeEquityPayload p) =>
    _mcRangeEquities(
      hero: p.hero,
      villain: p.villain,
      board: p.board,
      iterations: p.iterations,
      seed: p.seed,
    );

/// The shared Monte-Carlo core: for each [hero] combo, sample the [villain]
/// range (weighted by reach) and a random runout, and tally showdown equity.
List<PackCombo> _mcRangeEquities({
  required List<WeightedCombo> hero,
  required List<WeightedCombo> villain,
  required List<int> board,
  required int iterations,
  required int seed,
}) {
  final rng = Random(seed);
  var boardMask = 0;
  for (final c in board) {
    boardMask |= 1 << c;
  }
  final deck = [
    for (var c = 0; c < 52; c++)
      if ((boardMask >> c) & 1 == 0) c
  ];
  final need = 5 - board.length;

  // Villain sampling table: cumulative reach over combos that don't collide
  // with the board. A uniform range (all reach equal) reduces to uniform draws.
  final vParsed = <_Parsed>[];
  final vCum = <double>[];
  var vTotal = 0.0;
  for (final v in villain) {
    if (v.reach <= 0) continue;
    final p = _parseOne(v.name);
    if (p == null || (p.mask & boardMask) != 0) continue;
    vTotal += v.reach;
    vParsed.add(p);
    vCum.add(vTotal);
  }
  final out = <PackCombo>[];
  if (vParsed.isEmpty || vTotal <= 0) return out;

  final hand = List<int>.filled(7, 0);
  for (var b = 0; b < board.length; b++) {
    hand[b] = board[b];
  }

  for (final hc in hero) {
    final h = _parseOne(hc.name);
    if (h == null || (h.mask & boardMask) != 0) continue;
    var won = 0.0;
    var trials = 0;
    var guard = 0;
    final maxGuard = iterations * 40;
    while (trials < iterations && guard < maxGuard) {
      guard++;
      final v = vParsed[_lowerBound(vCum, rng.nextDouble() * vTotal)];
      if ((v.mask & (boardMask | h.mask)) != 0) continue;
      // Deal the runout, rejecting collisions (no-op on the river, need == 0).
      var runMask = boardMask | h.mask | v.mask;
      var ok = true;
      for (var k = 0; k < need; k++) {
        final c = deck[rng.nextInt(deck.length)];
        if ((runMask >> c) & 1 == 1) {
          ok = false;
          break;
        }
        runMask |= 1 << c;
        hand[board.length + k] = c;
      }
      if (!ok) continue;
      hand[5] = h.c1;
      hand[6] = h.c2;
      final hv = evaluate7(hand);
      hand[5] = v.c1;
      hand[6] = v.c2;
      final vv = evaluate7(hand);
      if (hv > vv) {
        won += 1;
      } else if (hv == vv) {
        won += 0.5;
      }
      trials++;
    }
    if (trials == 0) continue;
    out.add(PackCombo(
      comboId: hc.comboId,
      reach: hc.reach,
      equity: won / trials,
      evPassive: null,
      freqs: const [],
      evs: const [],
    ));
  }
  return out;
}

/// First index into the cumulative-weight array [cum] whose value is > [x].
int _lowerBound(List<double> cum, double x) {
  var lo = 0, hi = cum.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

class _Parsed {
  final int c1, c2, mask;
  _Parsed(this.c1, this.c2) : mask = (1 << c1) | (1 << c2);
}

_Parsed? _parseOne(String n) {
  if (n.length != 4) return null;
  final a = parseCard(n.substring(0, 2));
  final b = parseCard(n.substring(2, 4));
  return (a < 0 || b < 0) ? null : _Parsed(a, b);
}
