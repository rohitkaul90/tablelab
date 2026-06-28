// GTO frequency library (DCE Q1) — Phase 2: the v1 SOLVE GRID runner.
//
// Solves the v1 vertical slice — scenario srp_late_v_bb (BTN open vs BB call,
// heads-up) over ~24 representative-texture flops × {medium, deep} SPR — and
// tabulates each solve into the checked-in frequency library
// (tool/solver/gto_freq_library.json). Operator-only; invokes the licensed
// TexasSolver via run_solver.dart. Design: launch/GTO_FREQUENCY_LIBRARY.md.
//
// PARAMETERISATION (settled after a validation solve, 2026-06-28):
//  - A single-raised 100bb pot is DEEP on the flop (pot ~5.5bb, ~95bb behind →
//    SPR ~17). But the 'vol' bet profile (which alone is tractable that deep) has
//    NO raise action, so OOP cannot CHECK-RAISE and the solver compensates by
//    donk-LEADING ~80% — a fatal distortion for a FREQUENCY library (verified:
//    OOP/BB led 80% first-to-act on As Kd 7h under 'vol'). Faithful frequencies
//    REQUIRE a tree with raises (check-raise available).
//  - The 'multi' profile has bet+raise+allin (check-raise exists) but OOMs on
//    deep (SPR 15-20) spots. So v1 solves the SHALLOWER SRP regime — shallow
//    (SPR 3 ≈ 25bb) + medium (SPR 6 ≈ 40bb) — FAITHFULLY with 'multi'. This is
//    the tournament / short-stack SRP band; deep-cash (~100bb) is deferred until
//    it can be solved faithfully (size-capped tree / bigger machine).
//  - v1 thus covers check / bet-size / call / fold / raise / allin frequencies.
//    Flop+turn only (dumpRounds 2) to bound dump size.
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
const int kDumpRounds = 2; // flop + turn (v1; river deferred)
const String kBetProfile = 'multi'; // bet+raise+allin → faithful check-raise freqs
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

List<int> _ints(String flop) =>
    flop.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

/// Build the scenario's preflop ranges once: IP = BTN RFI, OOP = BB call vs BTN.
({String ip, String oop}) _scenarioRanges() {
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

/// A grid spot: a representative flop at one SPR regime.
SolverSpot _spot(String flop, double spr, String rangeIp, String rangeOop) {
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

/// Assemble gto_freq_library.json from all cached spot results.
void _writeLibrary(Map<String, dynamic> results) {
  final ranges = _scenarioRanges();
  final all = <FreqCell>[];
  final repFlops = <String, String>{};
  results.forEach((spotKey, v) {
    final m = v as Map<String, dynamic>;
    final flop = m['flop'] as String;
    for (final cj in (m['cells'] as List)) {
      final cell = _cellFromJson(cj as Map<String, dynamic>);
      all.add(cell);
      if (cell.street == 'flop') repFlops.putIfAbsent(cell.texture, () => flop);
    }
  });
  final merged = _mergeCells(all)
    ..sort((a, b) => b.reachWeight.compareTo(a.reachWeight));
  final streets = (merged.map((c) => c.street).toSet().toList()..sort()).join('+');
  final lib = FreqLibrary(
    meta: {
      'solver': 'TexasSolver',
      'bet_profile': kBetProfile,
      'dump_rounds': kDumpRounds,
      'streets': streets, // actual streets present (v1 grid was flop-only)
      'spr_reps': kSprReps,
      'note': 'v1: faithful check/bet-size/call/fold/raise/allin freqs (multi '
          'profile, check-raise available). Shallow+medium SPR (tournament/short '
          'SRP); deep-cash deferred. SPR keyed to the spot flop regime.',
      'generated_spots': results.length,
    },
    scenarios: {
      kScenario: ScenarioLib(ranges.ip, ranges.oop, repFlops, merged),
    },
  );
  File(kLibraryPath).writeAsStringSync(lib.toJsonString());
  stdout.writeln('Wrote $kLibraryPath: ${merged.length} cells from '
      '${results.length} spots (${repFlops.length} textures).');
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

  final ranges = _scenarioRanges();
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
      final spot = _spot(s.flop, s.sprVal, ranges.ip, ranges.oop);
      final tree = await solveRoot(spot,
          dumpRounds: kDumpRounds, betProfile: kBetProfile);
      final cells = tabulateSpot(tree.root,
          board: _ints(s.flop), sprBucket: s.spr, maxBoardLen: 4);
      results[key] = {
        'flop': s.flop,
        'spr': s.spr,
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
