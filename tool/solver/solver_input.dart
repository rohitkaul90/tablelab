// Maps a recorded TableLab [PokerHand] (or eval fixture) into a TexasSolver
// postflop spot: board + IP/OOP preflop ranges + pot + effective stack.
//
// POC SCOPE (see launch plan / tool/solver): single-raised, HEADS-UP-to-flop
// pots only, and a FLOP decision. Ranges come from the shared GTO chart keys
// (chart_keys.dart) + presets (gto_ranges.dart) — the same source the trust-pack
// villain model uses — so this exercises real reuse, not a bespoke range. Limped
// pots, 3-bet+ pots, multiway, and turn/river decisions throw [UnsupportedSpot]
// (handled by the follow-on, not this POC).

import 'package:tablelab/equity/chart_keys.dart';
import 'package:tablelab/models/hand_model.dart';

/// Two hole cards → range notation: "AA" (pair), "AKs" (suited), "AKo" (offsuit).
String _handNotation(List<String> cards) {
  const order = '23456789TJQKA';
  final a = cards[0], b = cards[1];
  final hi = order.indexOf(a[0]) >= order.indexOf(b[0]) ? a : b;
  final lo = identical(hi, a) ? b : a;
  if (hi[0] == lo[0]) return '${hi[0]}${lo[0]}';
  return '${hi[0]}${lo[0]}${hi[1] == lo[1] ? "s" : "o"}';
}

class UnsupportedSpot implements Exception {
  final String reason;
  UnsupportedSpot(this.reason);
  @override
  String toString() => 'UnsupportedSpot: $reason';
}

/// A fully-specified TexasSolver postflop spot, ready for `run_solver.dart`.
class SolverSpot {
  final List<String> board; // flop, e.g. ["Qc","9c","Ks"]
  final String rangeIp; // comma-joined notation, e.g. "AA,KK,AKs,..."
  final String rangeOop;
  final int pot; // chips in the pot entering the flop
  final int effStack; // effective stack entering the flop
  final int heroContribution; // chips hero committed entering the flop (C_hero)
  final String heroCombo; // hero's exact two cards, e.g. "AcJh"
  final bool heroIsIp;

  /// Solver action strings to follow from the root to hero's decision node.
  /// Empty when hero acts first on the flop (root IS hero's node); ["CHECK"]
  /// when hero is IP and villain checked to him.
  final List<String> heroPath;

  /// Human description of how the ranges were chosen (for the POC report).
  final String rangeTrail;

  SolverSpot({
    required this.board,
    required this.rangeIp,
    required this.rangeOop,
    required this.pot,
    required this.effStack,
    required this.heroContribution,
    required this.heroCombo,
    required this.heroIsIp,
    required this.heroPath,
    required this.rangeTrail,
  });

  /// Build a flop spot from a recorded hand. Throws [UnsupportedSpot] when the
  /// preflop/flop shape is outside the POC scope.
  factory SolverSpot.fromHand(PokerHand hand) {
    final ts = hand.tableSetup;
    final hero = hand.hero;
    if (hero == null || hero.holeCards == null || hero.holeCards!.length != 2) {
      throw UnsupportedSpot('hero hole cards missing');
    }
    if (hand.streets.length < 2 || hand.streets[1].street != Street.flop) {
      throw UnsupportedSpot('no flop street recorded');
    }
    final preflop = hand.streets[0];
    final flop = hand.streets[1];

    // Active-at-flop = seats that did not fold preflop.
    final folded = preflop.actions
        .where((a) => a.type == ActionType.fold)
        .map((a) => a.seat)
        .toSet();
    final active = hand.players
        .map((p) => p.seatIndex)
        .where((s) => !folded.contains(s))
        .toList();
    if (active.length != 2) {
      throw UnsupportedSpot('not heads-up to the flop (${active.length} players)');
    }
    if (!active.contains(ts.heroSeat)) {
      throw UnsupportedSpot('hero folded preflop');
    }

    // Classify the preflop line: exactly one raise (single-raised pot).
    final raises = preflop.actions.where((a) => a.type == ActionType.raise).toList();
    if (raises.isEmpty) {
      throw UnsupportedSpot('limped pot — not in the GTO charts (POC scope)');
    }
    if (raises.length > 1) {
      throw UnsupportedSpot('3-bet+ pot — outside POC scope');
    }
    final openerSeat = raises.first.seat;
    final callerSeat = active.firstWhere((s) => s != openerSeat);
    final openerLabel = ts.positionName(openerSeat);
    final callerLabel = ts.positionName(callerSeat);
    final trn = hand.isTournament;

    // Range keys from the shared chart-key mapping.
    final openerKey = rfiKey(openerLabel, trn);
    if (openerKey == null) {
      throw UnsupportedSpot('opener $openerLabel has no RFI chart');
    }
    final bucket = openerBucketForLabel(openerLabel);
    final callerKey = callKey(posClass(callerLabel), bucket, openerLabel, trn);
    final openerRange = presetByKey[openerKey];
    final callerRange = presetByKey[callerKey];
    if (openerRange == null || callerRange == null) {
      throw UnsupportedSpot('missing preset ($openerKey / $callerKey)');
    }

    // IP / OOP from postflop action order (first to act = OOP).
    final order = ts.postflopOrder(active);
    final oopSeat = order.first;
    final ipSeat = order.last;
    final rangeOf = {openerSeat: openerRange, callerSeat: callerRange};
    final keyOf = {openerSeat: openerKey, callerSeat: callerKey};

    // Pot entering the flop = sum of each seat's max preflop contribution
    // (includes folded blinds). Effective stack = min remaining of the two
    // active players (shortest-stack convention, mirrors villain_range).
    final contrib = <int, int>{};
    for (final a in preflop.actions) {
      final amt = a.amount;
      if (amt != null && amt > (contrib[a.seat] ?? 0)) contrib[a.seat] = amt;
    }
    final pot = contrib.values.fold(0, (s, v) => s + v);
    final stackOf = {for (final p in hand.players) p.seatIndex: p.startingStack};
    final effStack = active
        .map((s) => stackOf[s]! - (contrib[s] ?? 0))
        .reduce((a, b) => a < b ? a : b);

    // Path from root to hero's first flop decision.
    final heroIsIp = ts.heroSeat == ipSeat;
    final heroPath = <String>[];
    final first = flop.actions.isNotEmpty ? flop.actions.first : null;
    if (heroIsIp) {
      // OOP acts first; we can only cleanly follow an unambiguous CHECK.
      if (first == null || first.seat != oopSeat) {
        throw UnsupportedSpot('unexpected flop action order');
      }
      if (first.type == ActionType.check) {
        heroPath.add('CHECK');
      } else {
        throw UnsupportedSpot(
            'hero IP faced a sized bet — needs bet-size matching (follow-on)');
      }
    } else {
      // Hero is OOP and acts first → root node is hero's decision.
      if (first == null || first.seat != ts.heroSeat) {
        throw UnsupportedSpot('unexpected flop action order');
      }
    }

    // Force-include hero's ACTUAL hand in hero's range — Pluribus / real players
    // hold hands outside the textbook chart, and the solver has no strategy for a
    // combo absent from the range. Adding the one notation (standard practice) keeps
    // every recorded spot solvable; it perturbs the range by a single combo.
    final ipSet = {...rangeOf[ipSeat]!};
    final oopSet = {...rangeOf[oopSeat]!};
    final heroNote = _handNotation(hero.holeCards!);
    (heroIsIp ? ipSet : oopSet).add(heroNote);

    return SolverSpot(
      board: List<String>.from(flop.communityCards),
      rangeIp: (ipSet.toList()..sort()).join(','),
      rangeOop: (oopSet.toList()..sort()).join(','),
      pot: pot,
      effStack: effStack,
      heroContribution: contrib[ts.heroSeat] ?? 0,
      heroCombo: hero.holeCards!.join(),
      heroIsIp: heroIsIp,
      heroPath: heroPath,
      rangeTrail: 'IP=${ts.positionName(ipSeat)} (${keyOf[ipSeat]}), '
          'OOP=${ts.positionName(oopSeat)} (${keyOf[oopSeat]}); '
          'pot $pot, eff $effStack (SPR ${(effStack / pot).toStringAsFixed(1)})',
    );
  }
}
