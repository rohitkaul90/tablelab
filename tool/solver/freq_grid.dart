// GTO frequency library (DCE Q1) — SOLVE GRID runner (phase 2b: turn cells).
//
// Solves the scenario srp_late_v_bb (BTN open vs BB call, heads-up) over ~24
// representative-texture flops × {shallow, medium} SPR and tabulates each solve
// into the checked-in frequency library (assets/gto_freq_library.json).
// Operator-only; invokes the licensed TexasSolver via run_solver.dart.
// Design: launch/GTO_FREQUENCY_LIBRARY.md + launch/GTO_FREQ_PHASE2B_TURN.md.
//
// PARAMETERISATION:
//  - SPR regime: shallow (SPR 3 ≈ 25bb) + medium (SPR 6 ≈ 40bb) — the tournament
//    / short-stack SRP band. Deep-cash (~100bb, flop SPR ~17) is deferred: the
//    raise-bearing tree OOMs there, and the raise-free 'vol' profile distorts OOP
//    by ~80% donk-leading (no check-raise).
//  - Bet profile 'turn' (phase 2b): flop tiered (bet 33/75 + raise + allin) AND
//    the TURN gets a raise + a second size, so turn check-raise exists and turn
//    frequencies are FAITHFUL. v1's 'multi' lacked a turn raise → turn cells were
//    donk-lead-distorted (the same flaw 'vol' has on the flop). River stays lean
//    (single size + allin) — not tabulated this phase.
//  - Streets: flop + turn (dumpRounds 2). Each cell is bucketed by the SPR at ITS
//    OWN street (the tabulator reconstructs the pot down the line) — a turn after
//    a bet-call sits in a shallower bucket than the flop, matching the live path.
//  - Covers check / bet-size / call / fold / raise / allin frequencies per street.
//
// Usage:
//   dart run tool/solver/freq_grid.dart            # full grid (resumes via cache)
//   dart run tool/solver/freq_grid.dart --limit 1  # smoke: solve the first spot
//   dart run tool/solver/freq_grid.dart --write     # (re)assemble the library JSON
//                                                   #   from cached spot results

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/chart_keys.dart';

import 'freq_tabulate.dart';
import 'run_solver.dart';
import 'solver_input.dart';

const String kScenario = 'srp_late_v_bb';
const int kDumpRounds = 2; // flop + turn (river deferred)
// 'turn' (phase 2b): flop tiered + TURN gets a raise so turn check-raise exists
// → faithful turn frequencies. 'multi' (v1) lacked a turn raise → turn cells
// would be donk-lead-distorted. River kept lean (not tabulated). The spot-key
// embeds the profile, so switching does NOT reuse the stale 'multi' flop cache.
const String kBetProfile = 'turn';
const String kResultsPath = 'tool/solver/freq_grid_results.json';
// The shipped library lives in assets/ (bundled for app/web, file-readable for
// the eval baker). The grid writes it there directly.
const String kLibraryPath = 'assets/gto_freq_library.json';

/// The spot's flop SPR regimes: name → representative SPR. Names match
/// `decision_context.sprBucket` (3 → shallow, 6 → medium). Deep (SPR>6) deferred:
/// 'multi' OOMs there and 'vol' distorts OOP (no check-raise) — see header.
const Map<String, double> kSprReps = {'shallow': 3.0, 'medium': 6.0};

/// ~24 representative flops, hand-picked to span the common texture cells
/// (suit × pairing × high-card × connectedness). Colliding cells just add mass.
const List<String> kRepFlops = [
  // rainbow, unpaired
  'As Kd 7h', 'Ah Qc Td', 'Ks 9h 4c', 'Js Td 9c',
  '9s 5h 2c', '8h 7c 6d', '7h 4c 2s', '6s 5d 4c',
  // two-tone, unpaired
  'Ad 9d 4s', 'Ah Qh Td', 'Kh 8h 3c', 'Qh Th 9c',
  '9c 6c 2d', 'Th 8h 7c', '7d 4d 2c', '6h 5h 3c',
  // monotone, unpaired
  'Kh Qh Jh', 'Ah 8h 3h', '9d 6d 3d', 'Td 9d 8d', '7s 5s 2s',
  // paired (always disconnected)
  'Ks Kh 7c', '8s 8d 3c', '5h 5c 2s', 'Ah Ac 9d', 'Qh Qc 6h',
];

/// Parse a "Th 8h 7c" flop to card ints. Public so calib_turn.dart reuses it.
List<int> flopInts(String flop) =>
    flop.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

/// Build the scenario's preflop ranges once: IP = BTN RFI, OOP = BB call vs BTN.
/// Public so the calibration runner solves the SAME ranges as the full grid
/// (no second copy to drift) — it throws a descriptive error on a missing preset.
({String ip, String oop}) scenarioRanges() {
  final ipKey = rfiKey('BTN', false); // cash_rfi_btn
  final oopKey = callKey('bb', openerBucketForLabel('BTN'), 'BTN', false);
  final ip = presetByKey[ipKey];
  final oop = presetByKey[oopKey];
  if (ip == null || oop == null) {
    throw StateError('missing scenario ranges ($ipKey / $oopKey)');
  }
  return (
    ip: (ip.toList()..sort()).join(','),
    oop: (oop.toList()..sort()).join(','),
  );
}

/// A grid spot: a representative flop at one SPR regime. Public so calib_turn.dart
/// builds spots identically (pot 10; only SPR matters).
SolverSpot gridSpot(String flop, double spr, String rangeIp, String rangeOop) {
  const pot = 10; // absolute scale is irrelevant — only SPR matters
  return SolverSpot(
    board: flop.split(' ').where((t) => t.isNotEmpty).toList(),
    rangeIp: rangeIp,
    rangeOop: rangeOop,
    pot: pot,
    effStack: (spr * pot).round(),
    heroContribution: 0, // unused by solveRoot (whole-tree walk)
    heroCombo: 'AhKs', // unused
    heroIsIp: true, // unused
    heroPath: const [], // unused
    rangeTrail: '$kScenario SPR ${spr.toStringAsFixed(0)}',
  );
}

String _spotKey(String flop, String sprName) =>
    '${flop.replaceAll(' ', '')}|$sprName|$kBetProfile|dr$kDumpRounds';

Map<String, dynamic> _loadResults() {
  final f = File(kResultsPath);
  if (!f.existsSync()) return {};
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void _saveResults(Map<String, dynamic> results) {
  File(kResultsPath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
}

/// Merge FreqCells sharing a key (texture×spr×street×pos×facing×class) by
/// reach-mass weighting — combines cells from different flops/SPR solves.
List<FreqCell> _mergeCells(List<FreqCell> cells) {
  final byKey = <String, List<FreqCell>>{};
  for (final c in cells) {
    final k = [c.texture, c.sprBucket, c.street, c.position, c.facing, c.handClass]
        .join('@@');
    byKey.putIfAbsent(k, () => []).add(c);
  }
  final out = <FreqCell>[];
  byKey.forEach((_, group) {
    if (group.length == 1) {
      out.add(group.first);
      return;
    }
    final weighted = <String, double>{};
    var mass = 0.0;
    for (final c in group) {
      mass += c.reachWeight;
      c.freqs.forEach((a, f) => weighted[a] = (weighted[a] ?? 0) + f * c.reachWeight);
    }
    final g = group.first;
    out.add(FreqCell(
      texture: g.texture,
      sprBucket: g.sprBucket,
      street: g.street,
      position: g.position,
      facing: g.facing,
      handClass: g.handClass,
      freqs: {for (final e in weighted.entries) e.key: e.value / mass},
      reachWeight: mass,
    ));
  });
  return out;
}

FreqCell _cellFromJson(Map<String, dynamic> j) => FreqCell(
      texture: j['texture'] as String,
      sprBucket: j['spr_bucket'] as String,
      street: j['street'] as String,
      position: j['position'] as String,
      facing: j['facing'] as String,
      handClass: j['hand_class'] as String,
      freqs: {
        for (final e in (j['freqs'] as Map).entries)
          e.key as String: (e.value as num).toDouble()
      },
      reachWeight: (j['reach_weight'] as num).toDouble(),
    );

/// Assemble gto_freq_library.json from cached spot results, folding in ONLY the
/// spots solved with the current ([kBetProfile], [kDumpRounds]) — so a
/// results.json that still holds a different profile's solves (e.g. a stale v1
/// 'multi' cache) can't blend its donk-distorted cells into this library.
void _writeLibrary(Map<String, dynamic> results) {
  final ranges = scenarioRanges();
  final all = <FreqCell>[];
  final repFlops = <String, String>{};
  var usedSpots = 0, skippedOtherProfile = 0;
  results.forEach((spotKey, v) {
    final m = v as Map<String, dynamic>;
    // Older records pre-date the stamp; fall back to the profile in the spotKey
    // (`flop|spr|PROFILE|drN`) so the filter still holds for them.
    final keyParts = spotKey.split('|');
    final profile =
        (m['profile'] as String?) ?? (keyParts.length >= 3 ? keyParts[2] : null);
    final dumpRounds = (m['dump_rounds'] as int?);
    if (profile != kBetProfile ||
        (dumpRounds != null && dumpRounds != kDumpRounds)) {
      skippedOtherProfile++;
      return;
    }
    usedSpots++;
    final flop = m['flop'] as String;
    for (final cj in (m['cells'] as List)) {
      final cell = _cellFromJson(cj as Map<String, dynamic>);
      all.add(cell);
      if (cell.street == 'flop') repFlops.putIfAbsent(cell.texture, () => flop);
    }
  });
  if (skippedOtherProfile > 0) {
    stdout.writeln('  (skipped $skippedOtherProfile cached spots from a '
        'different profile/dump-rounds)');
  }
  // Refuse to clobber the shipped library with an empty/degraded one. This fires
  // when the cache holds only OTHER-profile spots (e.g. rebuilding after the
  // kBetProfile flip but before any matching solve has run): every spot is
  // skipped, usedSpots==0, and writing here would replace the live library with
  // 0 cells — silently killing the GTO-frequency FACT in prod. Abort instead.
  if (usedSpots == 0 || all.isEmpty) {
    stderr.writeln('ABORT: no cached spots match the current profile '
        "('$kBetProfile', dumpRounds $kDumpRounds) — refusing to overwrite "
        '$kLibraryPath with an empty library. Run the grid to solve '
        '$kBetProfile spots first ($skippedOtherProfile spots skipped).');
    exitCode = 1;
    return;
  }
  final merged = _mergeCells(all)
    ..sort((a, b) => b.reachWeight.compareTo(a.reachWeight));
  final streets = (merged.map((c) => c.street).toSet().toList()..sort()).join('+');
  final lib = FreqLibrary(
    meta: {
      'solver': 'TexasSolver',
      'bet_profile': kBetProfile,
      'dump_rounds': kDumpRounds,
      'streets': streets, // actual streets present (flop+turn in phase 2b)
      'spr_reps': kSprReps,
      'note': 'phase 2b: faithful flop+turn check/bet-size/call/fold/raise/allin '
          'freqs ("turn" profile — turn check-raise available). Shallow+medium '
          'SPR (tournament/short SRP); deep-cash deferred. Each cell is keyed by '
          'the SPR at its OWN street (pot reconstructed down the line), so a turn '
          'after a bet-call buckets shallower than the flop.',
      'generated_spots': usedSpots,
    },
    scenarios: {
      kScenario: ScenarioLib(ranges.ip, ranges.oop, repFlops, merged),
    },
  );
  File(kLibraryPath).writeAsStringSync(lib.toJsonString());
  stdout.writeln('Wrote $kLibraryPath: ${merged.length} cells from '
      '$usedSpots spots (${repFlops.length} textures).');
}

Future<void> main(List<String> args) async {
  final writeOnly = args.contains('--write');
  final limitIdx = args.indexOf('--limit');
  final limit = limitIdx >= 0 && limitIdx + 1 < args.length
      ? int.tryParse(args[limitIdx + 1])
      : null;

  final results = _loadResults();

  if (writeOnly) {
    _writeLibrary(results);
    return;
  }

  final ranges = scenarioRanges();
  final spots = <({String flop, String spr, double sprVal})>[];
  for (final flop in kRepFlops) {
    for (final e in kSprReps.entries) {
      spots.add((flop: flop, spr: e.key, sprVal: e.value));
    }
  }

  var solved = 0, skipped = 0, failed = 0;
  final sw = Stopwatch()..start();
  for (var i = 0; i < spots.length; i++) {
    if (limit != null && solved >= limit) break;
    final s = spots[i];
    final key = _spotKey(s.flop, s.spr);
    if (results.containsKey(key)) {
      skipped++;
      continue;
    }
    stdout.writeln('[${i + 1}/${spots.length}] solving ${s.flop} SPR ${s.spr} …');
    try {
      final spot = gridSpot(s.flop, s.sprVal, ranges.ip, ranges.oop);
      final tree = await solveRoot(spot,
          dumpRounds: kDumpRounds, betProfile: kBetProfile);
      // pot is fixed at 10 in _spot; effStack = spr·pot. The tabulator re-derives
      // the SPR bucket per street (flop vs the shallower turn after chips go in).
      final cells = tabulateSpot(tree.root,
          board: flopInts(s.flop),
          pot0: spot.pot.toDouble(),
          effStack: spot.effStack.toDouble(),
          maxBoardLen: 4);
      results[key] = {
        'flop': s.flop,
        'spr': s.spr,
        // Stamp the profile/dump-rounds so a library rebuild folds in ONLY
        // matching-profile spots — a results.json carried over from a different
        // profile (e.g. v1 'multi') must not blend its cells into this library.
        'profile': kBetProfile,
        'dump_rounds': kDumpRounds,
        'exploitability': tree.exploitability,
        'wall_ms': tree.wallMs,
        'cells': [for (final c in cells) c.toJson()],
      };
      _saveResults(results); // checkpoint after every solve (resumable)
      solved++;
      stdout.writeln('    ✓ ${cells.length} cells · expl '
          '${tree.exploitability?.toStringAsFixed(2)}% · ${tree.wallMs ~/ 1000}s');
    } catch (e) {
      failed++;
      stdout.writeln('    ✗ $e');
    }
  }
  sw.stop();
  stdout.writeln('\nGrid: solved $solved, skipped $skipped, failed $failed '
      'in ${sw.elapsed.inMinutes}m.');

  if (results.isNotEmpty) _writeLibrary(results);
}
