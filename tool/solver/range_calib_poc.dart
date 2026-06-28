// DCE Q2 — Phase 1 proof of concept. For a few no-reads HU spots where hero is IP
// (so villain = OOP acts FIRST → the solver root is villain's flop node), print
// hero's pot equity vs villain's FULL flop range and vs each of villain's GTO
// reach-weighted action ranges (check / bet33 / bet75 …) — then the equity
// ENGINE's heuristic flop number for the same hand, side by side. This is the
// per-action divergence the Phase-2 batch will measure systematically.
//
//   dart run tool/solver/range_calib_poc.dart [maxSpots=3]

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';

import 'range_calib.dart';
import 'run_solver.dart';
import 'solver_input.dart';

Future<void> main(List<String> args) async {
  final maxSpots = args.isNotEmpty ? int.parse(args[0]) : 3;
  final dir = Directory('tool/eval/fixtures');

  var done = 0;
  for (final f in dir.listSync().whereType<File>()) {
    if (done >= maxSpots) break;
    if (!f.path.endsWith('.json')) continue;
    final fx = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    if (fx['reads'] is List && (fx['reads'] as List).isNotEmpty) continue; // no-reads only
    final hand = PokerHand.fromJson(fx['hand'] as Map<String, dynamic>);
    SolverSpot spot;
    try {
      spot = SolverSpot.fromHand(hand);
    } catch (_) {
      continue;
    }
    if (!spot.heroIsIp) continue; // POC: villain = OOP = the root node
    done++;

    final hero = [
      parseCard(spot.heroCombo.substring(0, 2)),
      parseCard(spot.heroCombo.substring(2, 4)),
    ];
    final board = spot.board.map(parseCard).toList();
    stdout.writeln('\n=== ${fx['id']}  board ${spot.board.join(" ")}  '
        'hero ${spot.heroCombo} (IP)  pot ${spot.pot} eff ${spot.effStack} '
        'SPR ${(spot.effStack / spot.pot).toStringAsFixed(1)} ===');

    final TreeSolveResult tree;
    try {
      tree = await solveRoot(spot, dumpRounds: 2, betProfile: 'vol');
    } catch (e) {
      stdout.writeln('  solve error: $e');
      continue;
    }
    final root = tree.root; // OOP (villain) flop node
    stdout.writeln('  (solve expl ${tree.exploitability?.toStringAsFixed(2) ?? "?"}%, '
        'root player ${root["player"]})');

    // Hero equity vs villain's whole flop range (no narrowing) = the baseline.
    final full = nodeFullRange(root);
    final eqFull = heroEquityVsWeightedRange(hero, board, full);
    stdout.writeln('  SOLVER: hero eq vs villain FULL range = '
        '${(eqFull * 100).toStringAsFixed(1)}%  (${full.length} combos)');

    // Hero equity vs each GTO reach-weighted action range.
    final actions = nodeActions(root);
    for (var i = 0; i < actions.length; i++) {
      final r = nodeActionRange(root, i);
      if (r.isEmpty) continue;
      final eq = heroEquityVsWeightedRange(hero, board, r);
      final mass = r.fold<double>(0, (s, c) => s + c.w);
      stdout.writeln('  SOLVER: villain ${actions[i].padRight(18)} → hero eq '
          '${(eq * 100).toStringAsFixed(1)}%  (${r.length} combos, mass '
          '${mass.toStringAsFixed(1)})');
    }

    // Equity ENGINE's heuristic flop number (narrowed on the fixture's ACTUAL
    // villain flop action) for reference.
    final flopAct = _villainFlopAction(hand);
    final check = await computeHandEquityCheck(hand, reads: const [], seed: 1234);
    StreetEquityCheck? flop;
    for (final s in check?.streets ?? const <StreetEquityCheck>[]) {
      if (s.street == Street.flop) flop = s;
    }
    stdout.writeln('  ENGINE: hero flop eq (heuristic narrowing on villain\'s '
        'recorded "${flopAct ?? "?"}") = '
        '${flop == null ? "n/a" : "${(flop.heroEquity * 100).toStringAsFixed(1)}%"}');
  }
  if (done == 0) {
    stdout.writeln('No no-reads hero-IP HU flop spots found.');
  }
}

/// The villain's (OOP, first-to-act) flop action type in the recorded hand.
String? _villainFlopAction(PokerHand hand) {
  for (final s in hand.streets) {
    if (s.street != Street.flop) continue;
    return s.actions.isEmpty ? null : s.actions.first.type.name;
  }
  return null;
}
