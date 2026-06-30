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

import 'freq_grid.dart' show flopInts, gridSpot, scenarioRanges;
import 'freq_tabulate.dart';
import 'run_solver.dart';

const String kProfile = 'turn';
const int kDumpRounds = 2;
const double kPot = 10;
const double kSpr = 6.0; // medium — the OOM-risk regime for a turn raise

// The wettest cell: two-tone connected (most turn cards swing it). One spot is
// enough to measure turn-tree time/OOM + confirm per-street SPR bucketing.
const List<String> kCalibFlops = ['Th 8h 7c'];

Future<void> main() async {
  // SAME ranges + spot builder the full grid uses (shared, so the calibration
  // can't silently solve a different spot than the shipped library).
  final r = scenarioRanges();
  stdout.writeln('Calibration: profile=$kProfile dumpRounds=$kDumpRounds '
      'SPR=$kSpr (medium)\n');

  for (final flop in kCalibFlops) {
    final spot = gridSpot(flop, kSpr, r.ip, r.oop);
    stdout.writeln('── $flop ─────────────────────────────');
    final sw = Stopwatch()..start();
    try {
      final tree = await solveRoot(spot,
          dumpRounds: kDumpRounds, betProfile: kProfile);
      sw.stop();
      final cells = tabulateSpot(tree.root,
          board: flopInts(flop), pot0: kPot, effStack: kSpr * kPot, maxBoardLen: 4);

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
