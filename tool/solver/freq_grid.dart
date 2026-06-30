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
//    / short-stack SRP band — PLUS deep (SPR 15 ≈ 100bb deep-cash). The faithful
//    'turn' raise-bearing tree can't be solved on a 32 GB box (whole-machine RAM
//    starvation, not one solve needing 32 GB), so deep is solved on a big-RAM
//    vCPU box (≥256 GB — an r7a.8xlarge / 256 GB cleared all 26 deep spots at
//    --parallel 4). A local re-solve can drop 'deep' from kSprReps; even if it
//    doesn't, _writeLibrary refuses to clobber the committed deep cells (see its
//    regime-drop guard). Faithfulness is unchanged (same 'turn' profile, not the
//    donk-distorting raise-free 'vol').
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

// The bet profile is ENV-OVERRIDABLE so a RIVER cycle runs as
//   TLSOLVE_PROFILE=river dart run tool/solver/freq_grid.dart
// without editing code, while the DEFAULT stays the shipped flop+turn config — so
// a plain rebuild / `--write` with no env reproduces the committed library IN SYNC
// (no code↔library desync). The spot key embeds profile+dump-rounds, so switching
// configs never reuses a stale cache from the other (e.g. v1 'multi' or 'turn').
final String kBetProfile =
    (Platform.environment['TLSOLVE_PROFILE'] ?? 'turn').toLowerCase();

/// Dump-rounds is DERIVED from the profile, never set independently. Each profile
/// fixes BOTH its bet tree AND how many streets it faithfully solves, so coupling
/// them removes a footgun: with two separate knobs a mismatched pair silently
/// solves one tree but tabulates another — dr3 with the lean-river 'turn' profile
/// bakes DONK-DISTORTED river cells; 'river' with dr2 burns the heaviest solve but
/// emits zero river cells; dr1/dr0 produce a flop-only library that clobbers the
/// committed turn cells (the regime-drop guard checks SPR buckets, NOT streets).
/// One knob = no mismatch, and only the two valid dump-rounds are reachable.
///   'turn'  → flop+turn       (dump_rounds 2). The shipped default.
///   'river' → flop+turn+river (dump_rounds 3; the deepest tree, big-RAM box).
/// RIVER OPERATOR NOTES (from the 2026-06-30 trial — see tool/solver/VCPU_RUNBOOK.md):
///  - River REQUIRES a big Dart heap or it OOMs parsing the dumps (despite free system
///    RAM): run `dart --old_gen_heap_size=200000 run tool/solver/freq_grid.dart …`.
///  - The Dart-side jsonDecode+tabulate of river dumps is a SERIAL single-isolate
///    bottleneck (~66 of 91 min on a 3-spot trial) that `--parallel` does NOT relieve —
///    a full river solve needs the tabulation parallelized (per-spot Isolate.run) /
///    lightened first. Don't launch a full river grid until that's fixed.
/// This map is ALSO the profile allow-list (a typo'd TLSOLVE_PROFILE is rejected
/// in main() rather than falling through to 'multi' in `_betSizes`).
const Map<String, int> kProfileDumpRounds = {'turn': 2, 'river': 3};
final int kDumpRounds = kProfileDumpRounds[kBetProfile] ?? 2;
const String kResultsPath = 'tool/solver/freq_grid_results.json';
// The shipped library lives in assets/ (bundled for app/web, file-readable for
// the eval baker). The grid writes it there directly.
const String kLibraryPath = 'assets/gto_freq_library.json';

/// The spot's flop SPR regimes: name → representative SPR. Names match
/// `decision_context.sprBucket` (3 → shallow, 6 → medium, >6 → deep). 'deep'
/// (SPR 15 ≈ 100bb deep-cash) can't be solved on a 32 GB box; it solves on a
/// big-RAM vCPU box (≥256 GB — an r7a.8xlarge cleared it). You CAN drop it back
/// to {shallow, medium} for a local re-solve, but you don't have to: a local run
/// that can't solve deep won't silently clobber the committed deep cells —
/// _writeLibrary refuses to drop an SPR regime the shipped library already has.
const Map<String, double> kSprReps = {'shallow': 3.0, 'medium': 6.0, 'deep': 15.0};

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
      // Drop never-reached singletons — a zero-reach cell carries no usable
      // strategy (and the lookup's minMass would suppress it anyway).
      if (group.first.reachWeight > 0) out.add(group.first);
      return;
    }
    final weighted = <String, double>{};
    var mass = 0.0;
    for (final c in group) {
      mass += c.reachWeight;
      c.freqs.forEach((a, f) => weighted[a] = (weighted[a] ?? 0) + f * c.reachWeight);
    }
    // The reach-weighted mean is undefined when the whole group has zero reach
    // mass (every f * 0 = 0, then 0 / 0 = NaN — which crashes the library's JSON
    // encode at write time). These are {texture,spr,street,pos,facing,class}
    // combos that are never actually reached in the solved strategy; drop them.
    if (mass <= 0) return;
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
  // Post-merge empty guard: _mergeCells drops zero-reach singletons + zero-mass
  // groups, so a non-empty `all` can still collapse to []. The pre-merge guard
  // above only catches the no-matching-spots case — guard the actual written
  // value too, never clobbering the shipped library with 0 cells.
  if (merged.isEmpty) {
    stderr.writeln('ABORT: $usedSpots matching spot(s) all tabulated to '
        'zero-mass/zero-reach cells — refusing to overwrite $kLibraryPath '
        'with 0 cells.');
    exitCode = 1;
    return;
  }
  // Regime-drop guard: refuse to ship a library that DROPS an SPR bucket the
  // committed one already covers. A local 32 GB re-solve can't solve the 'deep'
  // spots (they OOM in the external solver); those failures are swallowed
  // per-spot, and the empty-guard above only catches a fully-empty rebuild — so
  // without this, the rebuild would overwrite the committed deep cells with
  // nothing, silently regressing live deep-SPR coaching. Compare spr_bucket sets
  // against the existing asset; abort on any drop (override with
  // ALLOW_REGIME_DROP=1 for an intentional narrowing).
  final existing = File(kLibraryPath);
  if (existing.existsSync() &&
      Platform.environment['ALLOW_REGIME_DROP'] != '1') {
    try {
      final prev = jsonDecode(existing.readAsStringSync()) as Map<String, dynamic>;
      final prevScenario =
          (prev['scenarios'] as Map?)?[kScenario] as Map<String, dynamic>?;
      final prevCells = prevScenario?['cells'] as List?;
      if (prevCells != null) {
        final prevBuckets = {
          for (final c in prevCells) (c as Map)['spr_bucket'] as String
        };
        final newBuckets = {for (final c in merged) c.sprBucket};
        final dropped = (prevBuckets.difference(newBuckets).toList())..sort();
        if (dropped.isNotEmpty) {
          stderr.writeln('ABORT: the rebuilt library is missing SPR bucket(s) '
              '$dropped that the committed $kLibraryPath covers — refusing to '
              'clobber it (likely deep spots OOM\'d / were skipped on a '
              'small-RAM box). Solve the missing regime on a big-RAM box, or set '
              'ALLOW_REGIME_DROP=1 to override for an intentional narrowing.');
          exitCode = 1;
          return;
        }
      }
    } catch (_) {
      // Unreadable / old-format existing library — don't block the write on it.
    }
  }
  final streets = (merged.map((c) => c.street).toSet().toList()..sort()).join('+');
  final lib = FreqLibrary(
    meta: {
      'solver': 'TexasSolver',
      'bet_profile': kBetProfile,
      'dump_rounds': kDumpRounds,
      'streets': streets, // actual streets present (flop+turn in phase 2b)
      'spr_reps': kSprReps,
      'note': 'faithful $streets check/bet-size/call/fold/raise/allin freqs '
          '("$kBetProfile" profile — check-raise available on every tabulated '
          'street). Shallow+medium+deep SPR. Each cell is keyed by the SPR at its '
          'OWN street (pot reconstructed down the line), so a turn/river after a '
          'bet-call buckets shallower than the flop.',
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

  if (!kProfileDumpRounds.containsKey(kBetProfile)) {
    stderr.writeln('TLSOLVE_PROFILE="$kBetProfile" is not a grid profile '
        '(${kProfileDumpRounds.keys.join('/')}). The grid tabulates per-street '
        'GTO frequencies and needs a faithful multi-street profile.');
    exitCode = 64;
    return;
  }

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

  // --parallel N: run up to N spots concurrently (each console_solver still uses
  // TLSOLVE_THREADS worker threads). ONE orchestrator process; the parent isolate
  // is the single writer of results.json. Default 1 = the old sequential run. On
  // an M-core box set N ≈ M / TLSOLVE_THREADS (e.g. 96 vCPU / 8t → --parallel 12).
  final parIdx = args.indexOf('--parallel');
  final parallel = (parIdx >= 0 && parIdx + 1 < args.length
          ? int.tryParse(args[parIdx + 1])
          : null) ??
      1;
  if (parallel < 1) {
    stderr.writeln('--parallel must be >= 1');
    exitCode = 64;
    return;
  }

  // Spots still needing a solve (cached ones skipped), capped to --limit if set.
  // Each pending spot is claimed and solved exactly once by exactly one worker.
  final pending = <({String flop, String spr, double sprVal})>[];
  var skipped = 0;
  for (final s in spots) {
    if (results.containsKey(_spotKey(s.flop, s.spr))) {
      skipped++;
    } else if (limit == null || pending.length < limit) {
      pending.add(s);
    }
  }

  var solved = 0, failed = 0, started = 0, next = 0;
  final total = pending.length;
  final sw = Stopwatch()..start();
  stdout.writeln('Solving $total spot(s) — $parallel at a time, '
      '$skipped cached/skipped.');

  // Each worker drains the shared queue; `parallel` of them run concurrently. The
  // ONLY suspension point is `await solveRoot` (where the external solvers run in
  // parallel) — claiming an index (next++) and the results-mutate + _saveResults
  // block both run WITHOUT an await, so they are atomic w.r.t. other workers under
  // Dart's single-threaded isolate model: no race on results.json, no concurrent
  // map modification. Each console_solver call uses its own temp dir (see
  // _invokeSolver), so parallel solves never collide on dump files.
  Future<void> worker() async {
    while (true) {
      final i = next;
      if (i >= total) break;
      next++;
      final s = pending[i];
      final n = ++started;
      final key = _spotKey(s.flop, s.spr);
      stdout.writeln('[$n/$total] solving ${s.flop} SPR ${s.spr} …');
      try {
        final spot = gridSpot(s.flop, s.sprVal, ranges.ip, ranges.oop);
        final tree = await solveRoot(spot,
            dumpRounds: kDumpRounds, betProfile: kBetProfile);
        // --- atomic block (no await until the next loop turn) ---
        // pot is fixed at 10 in gridSpot; effStack = spr·pot. The tabulator
        // re-derives the SPR bucket per street (flop vs the shallower turn after
        // chips go in).
        final cells = tabulateSpot(tree.root,
            board: flopInts(s.flop),
            pot0: spot.pot.toDouble(),
            effStack: spot.effStack.toDouble(),
            // dr2 → 4 (stop at turn); dr3 → 5 (walk the river).
            maxBoardLen: kDumpRounds + 2);
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
        stdout.writeln('    ✓ [${s.flop} ${s.spr}] ${cells.length} cells · expl '
            '${tree.exploitability?.toStringAsFixed(2)}% · ${tree.wallMs ~/ 1000}s');
      } catch (e) {
        failed++;
        stdout.writeln('    ✗ [${s.flop} ${s.spr}] $e');
      }
    }
  }

  await Future.wait([for (var w = 0; w < parallel; w++) worker()]);
  sw.stop();
  stdout.writeln('\nGrid: solved $solved, skipped $skipped, failed $failed '
      'in ${sw.elapsed.inMinutes}m.');

  if (results.isNotEmpty) _writeLibrary(results);
}
