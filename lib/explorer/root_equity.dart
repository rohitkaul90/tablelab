// GTO Explorer — on-device equity for the player who has NOT acted yet.
//
// Packs store per-combo equity only for the ACTING player at each node, so at
// a street's very first decision (the flop root) the opponent's distribution
// has no stored source. Both full ranges are in the manifest and the board is
// known, so we Monte-Carlo it here — pure Dart (evaluator + a seeded PRNG),
// designed to run inside compute() once per spot and be cached.

import 'dart:math';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/evaluator.dart';

import 'pack_codec.dart';

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

/// Equity of every hero combo vs the villain range (uniform reach) on the
/// board, as synthetic [PackCombo]s (reach 1.0, no strategy/EV) — directly
/// feedable to the equity-curve builder. Top-level so compute() can run it.
List<PackCombo> computeRootEquities(RootEquityPayload p) {
  final rng = Random(p.seed);
  final hero = _parse(p.heroCombos);
  final villain = _parse(p.villainCombos);
  var boardMask = 0;
  for (final c in p.board) {
    boardMask |= 1 << c;
  }
  final deck = [
    for (var c = 0; c < 52; c++)
      if ((boardMask >> c) & 1 == 0) c
  ];
  final need = 5 - p.board.length;
  final out = <PackCombo>[];
  final hand = List<int>.filled(7, 0);
  for (var b = 0; b < p.board.length; b++) {
    hand[b] = p.board[b];
  }

  for (var i = 0; i < hero.length; i++) {
    final h = hero[i];
    if (h == null || (h.mask & boardMask) != 0) continue;
    var won = 0.0;
    var trials = 0;
    var guard = 0;
    while (trials < p.iterations && guard < p.iterations * 20) {
      guard++;
      final v = villain[rng.nextInt(villain.length)];
      if (v == null || (v.mask & (boardMask | h.mask)) != 0) continue;
      // Deal the runout, rejecting collisions.
      var runMask = boardMask | h.mask | v.mask;
      var ok = true;
      final run = <int>[];
      for (var k = 0; k < need; k++) {
        final c = deck[rng.nextInt(deck.length)];
        if ((runMask >> c) & 1 == 1) {
          ok = false;
          break;
        }
        runMask |= 1 << c;
        run.add(c);
      }
      if (!ok) continue;
      for (var k = 0; k < need; k++) {
        hand[p.board.length + k] = run[k];
      }
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
      comboId: i,
      reach: 1.0,
      equity: won / trials,
      evPassive: null,
      freqs: const [],
      evs: const [],
    ));
  }
  return out;
}

class _Parsed {
  final int c1, c2, mask;
  _Parsed(this.c1, this.c2) : mask = (1 << c1) | (1 << c2);
}

List<_Parsed?> _parse(List<String> names) => [
      for (final n in names)
        n.length == 4
            ? () {
                final a = parseCard(n.substring(0, 2));
                final b = parseCard(n.substring(2, 4));
                return (a < 0 || b < 0) ? null : _Parsed(a, b);
              }()
            : null,
    ];
