// DCE Q1 phase 2b — TURN-PROFILE CALIBRATION (one-off, operator-only).
//
// Solves a couple of the wettest medium-SPR spots under the new 'turn' bet
// profile (flop tiered + a TURN raise) and reports wall-time, exploitability,
// peak behaviour (OOM shows as a crash/timeout), and the resulting per-street
// SPR distribution of the tabulated cells. Run this BEFORE the full re-solve to
// confirm the turn tree is tractable at medium SPR and that turn cells now land
// in the correct (shallower) SPR buckets.
//
//   dart run tool/solver/calib_turn.dart
//
// Deletable after phase 2b ships.

import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/chart_keys.dart';

import 'freq_tabulate.dart';
import 'run_solver.dart';
import 'solver_input.dart';

const String kProfile = 'turn';
const int kDumpRounds = 2;
const double kPot = 10;
const double kSpr = 6.0; // medium — the OOM-risk regime for a turn raise

// The wettest cell: two-tone connected (most turn cards swing it). One spot is
// enough to measure turn-tree time/OOM + confirm per-street SPR bucketing.
const List<String> kCalibFlops = ['Th 8h 7c'];

({String ip, String oop}) _ranges() {
  final ip = presetByKey[rfiKey('BTN', false)]!;
  final oop = presetByKey[callKey('bb', openerBucketForLabel('BTN'), 'BTN', false)]!;
  return (
    ip: (ip.toList()..sort()).join(','),
    oop: (oop.toList()..sort()).join(','),
  );
}

List<int> _ints(String flop) =>
    flop.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

Future<void> main() async {
  final r = _ranges();
  stdout.writeln('Calibration: profile=$kProfile dumpRounds=$kDumpRounds '
      'SPR=$kSpr (medium)\n');

  for (final flop in kCalibFlops) {
    final spot = SolverSpot(
      board: flop.split(' ').where((t) => t.isNotEmpty).toList(),
      rangeIp: r.ip,
      rangeOop: r.oop,
      pot: kPot.round(),
      effStack: (kSpr * kPot).round(),
      heroContribution: 0,
      heroCombo: 'AhKs',
      heroIsIp: true,
      heroPath: const [],
      rangeTrail: 'calib',
    );
    stdout.writeln('── $flop ─────────────────────────────');
    final sw = Stopwatch()..start();
    try {
      final tree = await solveRoot(spot,
          dumpRounds: kDumpRounds, betProfile: kProfile);
      sw.stop();
      final cells = tabulateSpot(tree.root,
          board: _ints(flop), pot0: kPot, effStack: kSpr * kPot, maxBoardLen: 4);

      // Per-street × SPR-bucket cell counts + reach mass.
      final byStreetSpr = <String, int>{};
      final massByStreetSpr = <String, double>{};
      for (final c in cells) {
        final k = '${c.street}/${c.sprBucket}';
        byStreetSpr[k] = (byStreetSpr[k] ?? 0) + 1;
        massByStreetSpr[k] = (massByStreetSpr[k] ?? 0) + c.reachWeight;
      }
      stdout.writeln('  ✓ ${(sw.elapsed.inMilliseconds / 1000).toStringAsFixed(0)}s'
          ' · expl ${tree.exploitability?.toStringAsFixed(2)}%'
          ' · ${cells.length} cells');
      final keys = byStreetSpr.keys.toList()..sort();
      for (final k in keys) {
        stdout.writeln('     $k: ${byStreetSpr[k]} cells, '
            'mass ${massByStreetSpr[k]!.toStringAsFixed(1)}');
      }
    } catch (e) {
      sw.stop();
      stdout.writeln('  ✗ FAILED after '
          '${(sw.elapsed.inMilliseconds / 1000).toStringAsFixed(0)}s: $e');
    }
    stdout.writeln();
  }
}
