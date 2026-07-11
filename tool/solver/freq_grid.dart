// GTO frequency library (DCE Q1) — SOLVE GRID runner.
//
// Solves ONE scenario per run (TLSOLVE_SCENARIO, default srp_late_v_bb; see
// kScenarios) over ~26 representative-texture flops × that scenario's SPR
// regimes, and tabulates each solve into the checked-in frequency library
// (assets/gto_freq_library.json) — which holds EVERY cached scenario's cells.
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
//                                                   #   from ALL cached scenarios
//   TLSOLVE_SCENARIO=3bp_bb_v_btn dart run …        # solve a different scenario
//   TLSOLVE_FLOPS=all1755 dart run …                # FULL-DENSITY flop set
//     (rep = the 26 curated flops (default) | all1755 = every canonical
//      suit-isomorphic flop | file:<path> = newline-separated flop list —
//      slice a bulk run across boxes)
//   TLSOLVE_DUMP_FMT=bin dart run …                 # TLSD binary dumps (~10×
//     smaller, small-heap parse; json = oracle/packs; both = validation)
//   dart run tool/solver/freq_grid.dart --compact   # fold the per-scenario
//     .jsonl checkpoint shards into freq_grid_results.json (run before seeding
//     a box — the launcher scp's the single results file)
//   … --emit-pack <dir>                             # ALSO write a GTO Explorer
//     pack per solved spot to <dir>/<scenario>/<flop>_<spr>/ (same parse pass —
//     see explorer_pack.dart / launch/GTO_EXPLORER.md). Only NEWLY-SOLVED spots
//     get packs: a cached spot is skipped entirely, so to pack it, delete its
//     results.json entry and let it re-solve (the run warns when this applies).

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/chart_keys.dart';

import 'flop_enum.dart';
import 'freq_tabulate.dart';
import 'run_solver.dart';
import 'solver_input.dart';
import 'spot_sched.dart';

/// One solvable scenario: a preflop range pair + the SPR regimes it's solved
/// at. The grid solves ONE scenario per run (TLSOLVE_SCENARIO); the library
/// holds every scenario's cells side by side (the live lookup keys on the
/// scenario string `_deriveScenarioKey` produces — keep keys in sync with
/// villain_range.dart).
class GridScenario {
  final String key;
  final String description;

  /// Flop SPR regimes for THIS scenario: bucket name → representative SPR.
  /// Names must be `decision_context.sprBucket` names, and each rep must LAND
  /// in its named bucket (the tabulator re-derives buckets from the SPR).
  final Map<String, double> sprReps;

  /// Preflop ranges (comma-joined notation), resolved from the shared GTO
  /// preset charts — the same source the live villain model uses.
  final ({String ip, String oop}) Function() ranges;

  const GridScenario({
    required this.key,
    required this.description,
    required this.sprReps,
    required this.ranges,
  });
}

({String ip, String oop}) _rangePair(String ipKey, String oopKey) {
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

final Map<String, GridScenario> kScenarios = {
  'srp_late_v_bb': GridScenario(
    key: 'srp_late_v_bb',
    description: 'BTN open vs BB call — heads-up single-raised (aggressor IP)',
    // The SRP band: tournament/short (3), mid (6), 100bb deep-cash (15).
    sprReps: const {'shallow': 3.0, 'medium': 6.0, 'deep': 15.0},
    ranges: () => _rangePair(
        rfiKey('BTN', false)!, // cash_rfi_btn
        callKey('bb', openerBucketForLabel('BTN'), 'BTN', false)),
  ),
  'srp_early_v_bb': GridScenario(
    key: 'srp_early_v_bb',
    description: 'Early-bucket (UTG-class) open vs BB call — heads-up '
        'single-raised (aggressor IP; tighter ranges than BTN-vs-BB)',
    // Same SRP band as srp_late_v_bb: the pot structure is identical (open
    // 2.5x + BB call), only the ranges differ. Representative opener range =
    // UTG RFI (the early bucket = UTG–MP; matches the live BB-defend pairing
    // cash_call_bb_vs_utg the lookup's opener bucketing uses).
    sprReps: const {'shallow': 3.0, 'medium': 6.0, 'deep': 15.0},
    ranges: () => _rangePair(
        rfiKey('UTG', false)!, // cash_rfi_utg
        callKey('bb', 'early', 'UTG', false)), // cash_call_bb_vs_utg
  ),
  'srp_middle_v_bb': GridScenario(
    key: 'srp_middle_v_bb',
    description: 'Middle-bucket (CO-class) open vs BB call — heads-up '
        'single-raised (aggressor IP)',
    sprReps: const {'shallow': 3.0, 'medium': 6.0, 'deep': 15.0},
    ranges: () => _rangePair(
        rfiKey('CO', false)!, // cash_rfi_co
        callKey('bb', 'middle', 'CO', false)), // cash_call_bb_vs_co
  ),
  'srp_sb_v_bb': GridScenario(
    key: 'srp_sb_v_bb',
    description: 'SB open vs BB call — blind-vs-blind single-raised. The FIRST '
        'scenario whose OPENER is OUT of position (SB acts first postflop; the '
        'BB caller is IP), so the SB range is the solver\'s OOP player and the '
        'BB defend range the IP player — the physical ip/oop cell keys the live '
        'lookup uses stay correct without any inversion.',
    // Same SRP band as the other single-raised scenarios — the solve pot is
    // normalized (only SPR matters), so the same reps apply. NOTE the bb
    // anchor differs though: the BvB flop pot is 5.0bb (SB open 2.5 + BB
    // call — the SB's blind is part of its open, NO dead SB), not the 5.5bb
    // the other SRPs share (see explorer preflop_ranges.kScenarioFlopPotBB).
    sprReps: const {'shallow': 3.0, 'medium': 6.0, 'deep': 15.0},
    ranges: () => _rangePair(
        callKey('bb', 'late', 'SB', false), // cash_call_bb_vs_sb — BB caller IP
        rfiKey('SB', false)!), // cash_rfi_sb — SB opener OOP
  ),
  '3bp_bb_v_btn': GridScenario(
    key: '3bp_bb_v_btn',
    description: 'BTN open, BB 3-bet, BTN call — heads-up 3-bet pot '
        '(aggressor OOP; condensed ranges)',
    // 3-bet-pot SPR band is inherently LOW: ~1 (25–40bb eff), ~2 (~60bb),
    // ~4 (100bb deep-cash ≈ pot 22.5bb, 89bb behind). Deep (>6) needs 250bb+
    // stacks — not modeled. Each rep lands squarely in its bucket
    // (committed ≤1 < shallow ≤3 < medium ≤6).
    sprReps: const {'committed': 1.0, 'shallow': 2.0, 'medium': 4.0},
    ranges: () => _rangePair(
        call3BetKey('ip', false), // cash_call_3b_ip — BTN continues vs the 3-bet
        threeBetKey('bb', 'late', false)), // cash_3b_bb_vs_btn — BB's 3-bet range
  ),
};

/// The scenario THIS run solves (env-selected; the library write folds in every
/// cached scenario regardless). Rejected in main() when unknown.
final String kScenario =
    (Platform.environment['TLSOLVE_SCENARIO'] ?? 'srp_late_v_bb').toLowerCase();

// The bet profile is ENV-OVERRIDABLE, but the DEFAULT MUST MATCH THE SHIPPED
// LIBRARY so a plain rebuild / `--write` with no env reproduces the committed
// library IN SYNC (no code↔library desync). The shipped library is now the RIVER
// config (flop+turn+river), so the default is 'river' — a stale 'turn' default
// would make `--write` rebuild a turn-only library and silently drop the river
// cells (the street-drop guard in _writeLibrary now backstops that, but the
// default must still track the shipped config). Bump this in lockstep whenever a
// new profile is shipped. The spot key embeds profile+dump-rounds, so switching
// configs never reuses a stale cache from the other (e.g. v1 'multi' or 'turn').
final String kBetProfile =
    (Platform.environment['TLSOLVE_PROFILE'] ?? 'river').toLowerCase();

/// Dump-rounds is DERIVED from the profile, never set independently. Each profile
/// fixes BOTH its bet tree AND how many streets it faithfully solves, so coupling
/// them removes a footgun: with two separate knobs a mismatched pair silently
/// solves one tree but tabulates another — dr3 with the lean-river 'turn' profile
/// bakes DONK-DISTORTED river cells; 'river' with dr2 burns the heaviest solve but
/// emits zero river cells; dr1/dr0 produce a flop-only library. (A rebuild that
/// drops a street this way is now caught by the regime-drop guard, which checks
/// BOTH SPR buckets AND streets against the committed asset.)
/// One knob = no mismatch, and only the two valid dump-rounds are reachable.
///   'turn'  → flop+turn       (dump_rounds 2).
///   'river' → flop+turn+river (dump_rounds 3; the deepest tree, big-RAM box).
///            The shipped default (see kBetProfile).
/// RIVER OPERATOR NOTES (from the 2026-06-30 trial — see tool/solver/VCPU_RUNBOOK.md):
///  - River REQUIRES a big Dart heap or it OOMs parsing the dumps (despite free system
///    RAM): run `dart --old_gen_heap_size=200000 run tool/solver/freq_grid.dart …`.
///  - The Dart-side jsonDecode+tabulate of river dumps is a serial single-thread,
///    GC-heavy bottleneck (~66 of 91 min on a 3-spot trial). It runs in a per-spot
///    SUBPROCESS (tool/solver/tabulate_one.dart — see the worker), NOT an
///    `Isolate.run`: isolates in a group SHARE one heap+GC, so N concurrent deep
///    parses thrashed a single GC (~4.7 effective cores across 10 parses). A
///    separate process per spot gives each parse its own heap+GC → `--parallel`
///    truly parallelizes across cores. RAM bounds --parallel (each subprocess holds
///    one big dump + its own big heap TLSOLVE_TABULATE_HEAP_MB): size N so
///    N × (dump + parse-heap) < system RAM, watch `free -g`. Put TMPDIR on a big
///    scratch (river dumps are ~15 GB each) — /dev/shm or a ≥500 GB volume.
/// This map is ALSO the profile allow-list (a typo'd TLSOLVE_PROFILE is rejected
/// in main() rather than falling through to 'multi' in `_betSizes`).
const Map<String, int> kProfileDumpRounds = {'turn': 2, 'river': 3};
final int kDumpRounds = kProfileDumpRounds[kBetProfile] ?? 2;
const String kResultsPath = 'tool/solver/freq_grid_results.json';
// The shipped library lives in assets/ (bundled for app/web, file-readable for
// the eval baker). The grid writes it there directly.
const String kLibraryPath = 'assets/gto_freq_library.json';

/// The SELECTED scenario's flop SPR regimes (see [GridScenario.sprReps]).
/// srp_late_v_bb's 'deep' (SPR 15 ≈ 100bb deep-cash) can't be solved on a
/// 32 GB box; it solves on a big-RAM vCPU box (≥256 GB — an r7a.8xlarge
/// cleared it). A local run that can't solve deep won't silently clobber the
/// committed deep cells — _writeLibrary refuses to drop an SPR regime the
/// shipped library already has.
final Map<String, double> kSprReps =
    kScenarios[kScenario]?.sprReps ?? const {};

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

/// The grid's flop set, selected by `TLSOLVE_FLOPS` (full-density plan WS2):
///   `rep`         — the 26 hand-picked representative flops (default; the
///                   shipped library's basis)
///   `all1755`     — every canonical suit-isomorphic flop (flop_enum.dart);
///                   full density, ~67× the spot count
///   `file:<path>` — newline-separated "As Kd 7h" flop list (slicing a bulk
///                   run across boxes, or a calibration subset)
List<String> _gridFlops() {
  final v = (Platform.environment['TLSOLVE_FLOPS'] ?? 'rep').trim();
  if (v.isEmpty || v.toLowerCase() == 'rep') return kRepFlops;
  if (v.toLowerCase() == 'all1755') return allIsoFlops();
  if (v.toLowerCase().startsWith('file:')) {
    final path = v.substring(5);
    final lines = File(path)
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    for (final l in lines) {
      final ints = flopInts(l);
      if (ints.length != 3 || ints.any((c) => c < 0)) {
        throw StateError('TLSOLVE_FLOPS file $path: bad flop line "$l" '
            '(want e.g. "As Kd 7h")');
      }
    }
    if (lines.isEmpty) throw StateError('TLSOLVE_FLOPS file $path is empty');
    return lines;
  }
  throw StateError('TLSOLVE_FLOPS="$v" not recognized (rep|all1755|file:<path>)');
}

String _flopSourceLabel() =>
    (Platform.environment['TLSOLVE_FLOPS'] ?? 'rep').trim().isEmpty
        ? 'rep'
        : (Platform.environment['TLSOLVE_FLOPS'] ?? 'rep').trim();

/// The SELECTED scenario's preflop ranges. Public so the calibration runner and
/// pack_spike solve the SAME ranges as the full grid (no second copy to drift);
/// throws a descriptive error on a missing preset or unknown scenario.
({String ip, String oop}) scenarioRanges() {
  final sc = kScenarios[kScenario];
  if (sc == null) {
    throw StateError('unknown TLSOLVE_SCENARIO "$kScenario" '
        '(${kScenarios.keys.join('/')})');
  }
  return sc.ranges();
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
    '$kScenario|${flop.replaceAll(' ', '')}|$sprName|$kBetProfile|dr$kDumpRounds';

/// Pre-multi-scenario cache keys had no scenario segment and implicitly meant
/// srp_late_v_bb — accept them so the carried-over river cache stays valid.
String _legacySpotKey(String flop, String sprName) =>
    '${flop.replaceAll(' ', '')}|$sprName|$kBetProfile|dr$kDumpRounds';

bool _isCached(Map<String, dynamic> results, String flop, String sprName) =>
    results.containsKey(_spotKey(flop, sprName)) ||
    (kScenario == 'srp_late_v_bb' &&
        results.containsKey(_legacySpotKey(flop, sprName)));

/// Per-scenario APPEND-ONLY checkpoint shard (full-density plan WS2). The
/// legacy whole-file `_saveResults` rewrite was O(total results) after EVERY
/// solve — already a 128 MB rewrite at 312 spots, quadratic and multi-GB at
/// 1,755-flop scale. A solved spot now appends ONE JSONL line
/// (`{"key": …, "entry": {…}}`) to its scenario's shard; `_loadResults` folds
/// shards over the legacy JSON (later lines win, so a re-solve supersedes).
String _shardPath([String? scenario]) =>
    'tool/solver/freq_grid_results.${scenario ?? kScenario}.jsonl';

Map<String, dynamic> _loadResults() {
  final out = <String, dynamic>{};
  final f = File(kResultsPath);
  if (f.existsSync()) {
    out.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }
  final dir = Directory('tool/solver');
  if (dir.existsSync()) {
    final shards = dir
        .listSync()
        .whereType<File>()
        .where((e) =>
            e.path.replaceAll('\\', '/').contains('/freq_grid_results.') &&
            e.path.endsWith('.jsonl'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final shard in shards) {
      for (final line in shard.readAsLinesSync()) {
        final l = line.trim();
        if (l.isEmpty) continue;
        try {
          final m = jsonDecode(l) as Map<String, dynamic>;
          out[m['key'] as String] = m['entry'];
        } catch (e) {
          // A torn tail line (kill mid-append) loses ONE spot, not the run.
          stderr.writeln('WARN: skipping bad shard line in ${shard.path}: $e');
        }
      }
    }
  }
  return out;
}

void _appendResult(String key, Map<String, dynamic> entry) {
  File(_shardPath()).writeAsStringSync(
      '${jsonEncode({'key': key, 'entry': entry})}\n',
      mode: FileMode.append,
      flush: true);
}

/// `--compact`: fold every shard into the legacy JSON and delete the shards —
/// run before seeding a box (the launcher scp's the single results file) or to
/// keep the shard set tidy between cycles.
///
/// CONCURRENCY GUARD (review finding): a grid run may be appending to a shard
/// WHILE compact runs. Deleting such a shard would permanently destroy the
/// spots appended after our snapshot read (paid solves, silently re-solved
/// later). So each shard's byte length is captured BEFORE the read, and a
/// shard is deleted only if its length is unchanged afterwards; a grown shard
/// is kept intact — its already-folded lines re-fold harmlessly on the next
/// load (later-wins with identical values), and the new lines survive.
void _compactResults() {
  final lengthsAtRead = <String, int>{};
  final dir = Directory('tool/solver');
  if (dir.existsSync()) {
    for (final e in dir.listSync().whereType<File>()) {
      final p = e.path.replaceAll('\\', '/');
      if (p.contains('/freq_grid_results.') && p.endsWith('.jsonl')) {
        lengthsAtRead[e.path] = e.lengthSync();
      }
    }
  }
  final merged = _loadResults();
  File(kResultsPath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(merged));
  var removed = 0, kept = 0;
  lengthsAtRead.forEach((path, len) {
    final f = File(path);
    if (!f.existsSync()) return;
    if (f.lengthSync() == len) {
      f.deleteSync();
      removed++;
    } else {
      kept++;
      stderr.writeln('WARN --compact: $path grew during compaction (a grid '
          'run is appending to it?) — kept intact; its lines re-fold next '
          'load. Re-run --compact after that run finishes.');
    }
  });
  stdout.writeln('compacted ${merged.length} results into $kResultsPath '
      '($removed shard(s) removed${kept > 0 ? ', $kept kept (in use)' : ''})');
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

/// Assemble gto_freq_library.json from cached spot results — EVERY cached
/// scenario, folding in ONLY the spots solved with the current
/// ([kBetProfile], [kDumpRounds]) — so a results.json that still holds a
/// different profile's solves (e.g. a stale v1 'multi' cache) can't blend its
/// donk-distorted cells into this library.
void _writeLibrary(Map<String, dynamic> results) {
  final cellsByScenario = <String, List<FreqCell>>{};
  final repFlopsByScenario = <String, Map<String, String>>{};
  final spotsByScenario = <String, int>{};
  var usedSpots = 0, skippedOtherProfile = 0, skippedUnknownScenario = 0;
  results.forEach((spotKey, v) {
    final m = v as Map<String, dynamic>;
    // Older records pre-date the stamps; their key format is
    // `flop|spr|PROFILE|drN` (scenario-less ⇒ srp_late_v_bb). New records
    // carry explicit 'scenario'/'profile'/'dump_rounds' stamps.
    final keyParts = spotKey.split('|');
    final profile =
        (m['profile'] as String?) ?? (keyParts.length >= 3 ? keyParts[2] : null);
    final dumpRounds = (m['dump_rounds'] as int?);
    if (profile != kBetProfile ||
        (dumpRounds != null && dumpRounds != kDumpRounds)) {
      skippedOtherProfile++;
      return;
    }
    final scenario = (m['scenario'] as String?) ?? 'srp_late_v_bb';
    if (!kScenarios.containsKey(scenario)) {
      // A cached scenario this code no longer defines — don't guess its ranges.
      skippedUnknownScenario++;
      return;
    }
    usedSpots++;
    spotsByScenario[scenario] = (spotsByScenario[scenario] ?? 0) + 1;
    final flop = m['flop'] as String;
    final cells = cellsByScenario.putIfAbsent(scenario, () => []);
    final repFlops = repFlopsByScenario.putIfAbsent(scenario, () => {});
    for (final cj in (m['cells'] as List)) {
      final cell = _cellFromJson(cj as Map<String, dynamic>);
      cells.add(cell);
      if (cell.street == 'flop') repFlops.putIfAbsent(cell.texture, () => flop);
    }
  });
  if (skippedUnknownScenario > 0) {
    stdout.writeln('  (skipped $skippedUnknownScenario cached spots from '
        'scenarios not defined in kScenarios)');
  }
  if (skippedOtherProfile > 0) {
    stdout.writeln('  (skipped $skippedOtherProfile cached spots from a '
        'different profile/dump-rounds)');
  }
  // Refuse to clobber the shipped library with an empty/degraded one. This fires
  // when the cache holds only OTHER-profile spots (e.g. rebuilding after the
  // kBetProfile flip but before any matching solve has run): every spot is
  // skipped, usedSpots==0, and writing here would replace the live library with
  // 0 cells — silently killing the GTO-frequency FACT in prod. Abort instead.
  if (usedSpots == 0 || cellsByScenario.isEmpty) {
    stderr.writeln('ABORT: no cached spots match the current profile '
        "('$kBetProfile', dumpRounds $kDumpRounds) — refusing to overwrite "
        '$kLibraryPath with an empty library. Run the grid to solve '
        '$kBetProfile spots first ($skippedOtherProfile spots skipped).');
    exitCode = 1;
    return;
  }
  // Merge per scenario. _mergeCells drops zero-reach singletons + zero-mass
  // groups, so a non-empty input can still collapse to []. That is NEVER ok
  // to paper over: for a BRAND-NEW scenario the scenario-drop guard below
  // can't fire (the committed library never contained it), so silently
  // omitting it would let the operator commit a "rebuilt" library believing
  // the scenario landed while its GTO FACT never fires in prod. Abort the
  // whole write instead (the pre-multi-scenario code aborted here too).
  final mergedByScenario = <String, List<FreqCell>>{};
  final emptyScenarios = <String>[];
  cellsByScenario.forEach((scenario, cells) {
    final merged = _mergeCells(cells)
      ..sort((a, b) => b.reachWeight.compareTo(a.reachWeight));
    if (merged.isEmpty) {
      emptyScenarios.add(scenario);
    } else {
      mergedByScenario[scenario] = merged;
    }
  });
  if (emptyScenarios.isNotEmpty) {
    stderr.writeln('ABORT: scenario(s) $emptyScenarios tabulated to ONLY '
        'zero-mass/zero-reach cells — refusing to write a library that '
        'silently omits them. Inspect those solves (bad ranges? broken '
        'tabulation?) before rebuilding.');
    exitCode = 1;
    return;
  }
  if (mergedByScenario.isEmpty) {
    stderr.writeln('ABORT: $usedSpots matching spot(s) all tabulated to '
        'zero-mass/zero-reach cells — refusing to overwrite $kLibraryPath '
        'with 0 cells.');
    exitCode = 1;
    return;
  }
  // Regime-drop guard: refuse to ship a library that DROPS a SCENARIO, an SPR
  // bucket, or a STREET the committed one already covers. Ways a rebuild
  // silently narrows coverage: (a) a local 32 GB re-solve can't solve 'deep'
  // (OOMs in the external solver), swallowed per-spot → the deep SPR bucket
  // vanishes; (b) a rebuild forced to an OLDER profile (TLSOLVE_PROFILE=turn,
  // dr2) re-solves as turn-only and drops the river STREET; (c) a results.json
  // that lost another scenario's cached spots (fresh checkout, pruned cache)
  // would silently drop that whole scenario. The empty-guard above only catches
  // a fully-empty rebuild. Compare the scenario set AND, per scenario, the
  // spr_bucket + street sets against the existing asset; abort on any drop
  // (override with ALLOW_REGIME_DROP=1 for an intentional narrowing).
  final existing = File(kLibraryPath);
  if (existing.existsSync() &&
      Platform.environment['ALLOW_REGIME_DROP'] != '1') {
    try {
      final prev = jsonDecode(existing.readAsStringSync()) as Map<String, dynamic>;
      final prevScenarios =
          (prev['scenarios'] as Map?)?.cast<String, dynamic>() ?? const {};
      for (final entry in prevScenarios.entries) {
        final scenario = entry.key;
        final prevCells =
            (entry.value as Map<String, dynamic>)['cells'] as List?;
        if (prevCells == null || prevCells.isEmpty) continue;
        final merged = mergedByScenario[scenario];
        if (merged == null) {
          stderr.writeln('ABORT: the rebuilt library DROPS scenario '
              "'$scenario' that the committed $kLibraryPath covers — refusing "
              'to clobber it (results.json is likely missing that scenario\'s '
              'cached spots). Restore the cache or set ALLOW_REGIME_DROP=1 '
              'for an intentional narrowing.');
          exitCode = 1;
          return;
        }
        final prevBuckets = {
          for (final c in prevCells) (c as Map)['spr_bucket'] as String
        };
        final newBuckets = {for (final c in merged) c.sprBucket};
        final droppedBuckets =
            (prevBuckets.difference(newBuckets).toList())..sort();
        final prevStreets = {
          for (final c in prevCells) (c as Map)['street'] as String
        };
        final newStreets = {for (final c in merged) c.street};
        final droppedStreets =
            (prevStreets.difference(newStreets).toList())..sort();
        if (droppedBuckets.isNotEmpty || droppedStreets.isNotEmpty) {
          final missing = [
            if (droppedBuckets.isNotEmpty) 'SPR bucket(s) $droppedBuckets',
            if (droppedStreets.isNotEmpty) 'street(s) $droppedStreets',
          ].join(' and ');
          stderr.writeln('ABORT: the rebuilt library is missing $missing that '
              "the committed $kLibraryPath covers for scenario '$scenario' — "
              'refusing to clobber it (likely deep spots OOM\'d on a small-RAM '
              'box, or a rebuild forced to an older TLSOLVE_PROFILE dropped a '
              'street). Solve the missing regime on a big-RAM box (or use the '
              'matching profile), or set ALLOW_REGIME_DROP=1 to override for '
              'an intentional narrowing.');
          exitCode = 1;
          return;
        }
      }
    } catch (_) {
      // Unreadable / old-format existing library — don't block the write on it.
    }
  }
  final allMerged = mergedByScenario.values.expand((c) => c);
  final streets =
      (allMerged.map((c) => c.street).toSet().toList()..sort()).join('+');
  final lib = FreqLibrary(
    meta: {
      'solver': 'TexasSolver',
      'bet_profile': kBetProfile,
      'dump_rounds': kDumpRounds,
      'streets': streets, // actual streets present (e.g. flop+turn+river)
      // Per-scenario SPR reps (each scenario is solved at its own regimes).
      'spr_reps': {
        for (final sc in mergedByScenario.keys)
          sc: kScenarios[sc]?.sprReps ?? const <String, double>{},
      },
      'note': 'faithful $streets check/bet-size/call/fold/raise/allin freqs '
          '("$kBetProfile" profile — check-raise available on every tabulated '
          'street). Each cell is keyed by the SPR at its OWN street (pot '
          'reconstructed down the line), so a turn/river after a bet-call '
          'buckets shallower than the flop.',
      'generated_spots': usedSpots,
      'spots_per_scenario': spotsByScenario,
    },
    scenarios: {
      for (final entry in mergedByScenario.entries)
        entry.key: ScenarioLib(
          kScenarios[entry.key]!.ranges().ip,
          kScenarios[entry.key]!.ranges().oop,
          repFlopsByScenario[entry.key] ?? const {},
          entry.value,
        ),
    },
  );
  File(kLibraryPath).writeAsStringSync(lib.toJsonString());
  final perScenario = mergedByScenario.entries
      .map((e) => '${e.key} ${e.value.length}')
      .join(', ');
  stdout.writeln('Wrote $kLibraryPath: '
      '${allMerged.length} cells from $usedSpots spots ($perScenario).');
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
  if (!kScenarios.containsKey(kScenario)) {
    stderr.writeln('TLSOLVE_SCENARIO="$kScenario" is not a defined scenario '
        '(${kScenarios.keys.join('/')}).');
    exitCode = 64;
    return;
  }

  if (args.contains('--compact')) {
    _compactResults();
    return;
  }

  final results = _loadResults();

  if (writeOnly) {
    _writeLibrary(results);
    return;
  }

  final ranges = scenarioRanges();
  final gridFlops = _gridFlops();
  stdout.writeln('flop source: ${_flopSourceLabel()} (${gridFlops.length} '
      'flops × ${kSprReps.length} SPRs)');
  final spots = <({String flop, String spr, double sprVal})>[];
  for (final flop in gridFlops) {
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

  // --emit-pack <dir>: have each spot's tabulate_one subprocess ALSO generate
  // its GTO Explorer pack (one jsonDecode, two outputs). Explicit dir, no
  // default — packs are hundreds of MB per spot on the big scenarios.
  final packIdx = args.indexOf('--emit-pack');
  final emitPackRoot = packIdx >= 0 && packIdx + 1 < args.length
      ? args[packIdx + 1]
      : null;
  if (packIdx >= 0 && emitPackRoot == null) {
    stderr.writeln('--emit-pack needs a target directory');
    exitCode = 64;
    return;
  }
  // Pack emission walks the JSON dump (explorer_pack is not TLSD-adapted —
  // packs are only emitted on curated 26-flop runs, never the full-density
  // bulk). An EXPLICIT bin + packs is an intent conflict → fail fast; with
  // packs on, the solve below forces JSON regardless of the format default
  // (forceJsonDump), so a flipped default can't silently break pack runs.
  if (emitPackRoot != null && solverDumpFmt() == 'bin' &&
      (Platform.environment['TLSOLVE_DUMP_FMT'] ?? '').isNotEmpty) {
    stderr.writeln('--emit-pack requires the JSON dump: unset '
        'TLSOLVE_DUMP_FMT=bin (use json or both) when emitting packs.');
    exitCode = 64;
    return;
  }
  // The effective format of THIS run's dumps — drives the parse footprints
  // (JSON parses need the giant heap; TLSD a few GB).
  final dumpFmtEnv = emitPackRoot != null ? 'json' : solverDumpFmt();

  // Spots still needing a solve (cached ones skipped), capped to --limit if set.
  // Each pending spot is claimed and solved exactly once by exactly one worker.
  // TLSOLVE_MAX_SPOT_GB skips (never fails) spots whose predicted solve RAM
  // exceeds it — a small-RAM box grinds the shallow/medium classes while a big
  // box takes deep (the split is pure env policy; see spot_sched.dart).
  final maxSpotGb =
      double.tryParse(Platform.environment['TLSOLVE_MAX_SPOT_GB'] ?? '');
  final pending = <({String flop, String spr, double sprVal})>[];
  var skipped = 0, skippedTooBig = 0;
  for (final s in spots) {
    if (_isCached(results, s.flop, s.spr)) {
      skipped++;
    } else if (maxSpotGb != null &&
        spotFootprint(s.sprVal, dumpFmt: dumpFmtEnv).solveGb > maxSpotGb) {
      skippedTooBig++;
    } else if (limit == null || pending.length < limit) {
      pending.add(s);
    }
  }
  if (skippedTooBig > 0) {
    stdout.writeln('⚠ TLSOLVE_MAX_SPOT_GB=$maxSpotGb: $skippedTooBig spot(s) '
        'skipped as too big for this box (solve them on a bigger one).');
  }

  // Ordering: LPT within a footprint class, then INTERLEAVED round-robin
  // across classes (largest class first in each round). Strict LPT alone puts
  // every deep spot first — on a RAM-tight box only ~2-4 deep claims fit, so
  // all workers block on deep admissions while the shallow work that could
  // fill the idle cores sits queued BEHIND hundreds of deep spots (~50% CPU
  // idle through the whole deep phase). Interleaving keeps deep spots
  // saturating the RAM budget from the start (their long tails still overlap
  // the backfill — the original LPT motivation) while medium/shallow flow
  // around them and keep the cores busy. Stable within a class (explicit
  // original-index tie-break — Dart's sort is not stable).
  final origIdx = {for (var i = 0; i < pending.length; i++) pending[i]: i};
  final byClass = <double, List<({String flop, String spr, double sprVal})>>{};
  for (final s in pending) {
    byClass
        .putIfAbsent(
            spotFootprint(s.sprVal, dumpFmt: dumpFmtEnv).solveGb, () => [])
        .add(s);
  }
  final classOrder = byClass.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final g in classOrder) {
    byClass[g]!.sort((a, b) {
      final ea = spotFootprint(a.sprVal, dumpFmt: dumpFmtEnv).estMinutes;
      final eb = spotFootprint(b.sprVal, dumpFmt: dumpFmtEnv).estMinutes;
      final c = eb.compareTo(ea);
      return c != 0 ? c : origIdx[a]!.compareTo(origIdx[b]!);
    });
  }
  pending.clear();
  var remaining = true;
  while (remaining) {
    remaining = false;
    for (final g in classOrder) {
      final list = byClass[g]!;
      if (list.isNotEmpty) {
        pending.add(list.removeAt(0));
        remaining = remaining || list.isNotEmpty;
      }
    }
  }

  // Admission budget: workers still cap at --parallel, but each phase's
  // (RAM, threads) claim must ALSO fit the box budget — so a high --parallel
  // is safe (deep spots' 100 GB claims throttle actual concurrency) and cores
  // stop idling behind a worst-case cap. See spot_sched.dart.
  final budget = ResourceBudget.fromEnv();
  final solverThreads =
      int.tryParse(Platform.environment['TLSOLVE_THREADS'] ?? '') ?? 8;

  var solved = 0, failed = 0, started = 0, next = 0;
  final total = pending.length;
  final sw = Stopwatch()..start();
  stdout.writeln('Solving $total spot(s) — up to $parallel workers, budget '
      '${budget.totalGb.toStringAsFixed(0)} GB / ${budget.totalThreads} '
      'threads (${solverThreads}t per solve), $skipped cached/skipped.');

  if (args.contains('--sched-dry-run')) {
    stdout.writeln('sched dry run — planned order (LPT):');
    for (final s in pending) {
      final fp = spotFootprint(s.sprVal, dumpFmt: dumpFmtEnv);
      stdout.writeln('  ${s.flop} ${s.spr}: solve ${fp.solveGb} GB/'
          '${solverThreads}t ~${fp.estMinutes}min, parse ${fp.parseGb} GB/1t');
    }
    return;
  }
  if (emitPackRoot != null && skipped > 0) {
    stdout.writeln('⚠ --emit-pack: $skipped cached spot(s) will NOT get packs '
        '(only newly-solved spots do) — delete their results.json entries to '
        're-solve them with pack emission.');
  }

  // Each worker drains the shared queue; `parallel` of them run concurrently. The
  // suspension points are `await solveToFile` (the external solvers run in parallel)
  // and `await Process.run(tabulate_one)` (the parse+tabulate runs in a separate
  // process, so several spots tabulate on separate cores with independent heaps/GC).
  // Both let other workers proceed; claiming an index (next++) and the results-mutate +
  // _appendResult block run WITHOUT an await, so they stay atomic w.r.t. other
  // workers under Dart's single-threaded main isolate: no race on the shard file, no
  // concurrent map modification (the append is a single synchronous O(spot) write —
  // the old whole-file _saveResults rewrite was O(total) per solve). Each solve uses
  // its own temp dir (see _runSolverToDump), so parallel solves never collide on
  // dump files.
  Future<void> worker() async {
    while (true) {
      final i = next;
      if (i >= total) break;
      next++;
      final s = pending[i];
      final key = _spotKey(s.flop, s.spr);
      final fp = spotFootprint(s.sprVal, dumpFmt: dumpFmtEnv);
      DumpSolve? ds;
      // Phase claims: solve holds (solveGb, solver threads); tabulate swaps
      // down to (parseGb, 1 thread). Track what we hold so the finally can
      // release exactly once whatever phase failed.
      var heldGb = 0.0;
      var heldThreads = 0;
      try {
        await budget.acquire(fp.solveGb, solverThreads);
        heldGb = fp.solveGb;
        heldThreads = solverThreads;
        final n = ++started;
        stdout.writeln('[$n/$total] solving ${s.flop} SPR ${s.spr} '
            '(${fp.solveGb.toStringAsFixed(0)} GB claim) …');
        final spot = gridSpot(s.flop, s.sprVal, ranges.ip, ranges.oop);
        // Pack runs force JSON (explorer_pack walks the Map tree) no matter
        // what TLSOLVE_DUMP_FMT/its default says.
        ds = await solveToFile(spot,
            dumpRounds: kDumpRounds,
            betProfile: kBetProfile,
            forceJsonDump: emitPackRoot != null);
        // Solve finished — swap the claim down to the parse footprint before
        // the tabulate subprocess (frees ~most of a deep spot's RAM for the
        // next admission the moment the solver exits).
        budget.release(heldGb, heldThreads);
        heldGb = 0;
        heldThreads = 0;
        await budget.acquire(fp.parseGb, 1);
        heldGb = fp.parseGb;
        heldThreads = 1;
        // Capture the scalars BEFORE the Process.run await (avoids relying on
        // null-promotion of `ds` surviving the await).
        final dumpPath = ds.dumpPath;
        final expl = ds.exploitability;
        final wallMs = ds.wallMs;
        // pot is fixed at 10 in gridSpot; effStack = spr·pot; the tabulator
        // re-derives the SPR bucket per street (flop vs the shallower turn/river
        // after chips go in). dr2 → maxBoardLen 4 (turn); dr3 → 5 (river).
        final pot0 = spot.pot.toDouble();
        final effStack = spot.effStack.toDouble();
        final maxLen = kDumpRounds + 2;
        // Parse + tabulate the dump in a SEPARATE PROCESS (tool/solver/tabulate_one.dart)
        // — NOT an Isolate. Isolate.run put every concurrent parse in ONE shared
        // isolate-group heap, so N deep-river dumps (~15 GB each) contended on a
        // SINGLE GC and stalled each other (measured: 10 parses shared ~4.7 cores,
        // ~2 spots/hr on a 128-vCPU box — see tool/solver/VCPU_RUNBOOK.md). A
        // subprocess gives each parse its own heap + GC, so `--parallel` truly
        // parallelizes the (single-threaded, GC-heavy) jsonDecode+walk across cores.
        // Each subprocess gets a big heap (TLSOLVE_TABULATE_HEAP_MB, default 80 GB);
        // the main grid process never holds a giant dump. Cells come back via a file
        // (not stdout) so a big list never buffers through Process.run.
        final outPath = '$dumpPath.cells.json';
        final tabHeapMb = int.tryParse(
                Platform.environment['TLSOLVE_TABULATE_HEAP_MB'] ?? '') ??
            80000;
        final packDir = emitPackRoot == null
            ? null
            : '$emitPackRoot/$kScenario/'
                '${s.flop.replaceAll(' ', '')}_${s.spr}';
        final res = await Process.run(Platform.resolvedExecutable, [
          '--old_gen_heap_size=$tabHeapMb',
          'run',
          'tool/solver/tabulate_one.dart',
          dumpPath,
          outPath,
          s.flop.replaceAll(' ', ''),
          pot0.toString(),
          effStack.toString(),
          maxLen.toString(),
          if (packDir != null) ...['--emit-pack', packDir, kScenario, s.spr],
        ]);
        if (res.exitCode != 0) {
          throw StateError('tabulate_one exit ${res.exitCode}: '
              '${(res.stderr as String).trim()}');
        }
        if (packDir != null) {
          // Surface the subprocess's pack report (sizes/EV coverage/timings)
          // in the grid log — it's the only visibility into pack output.
          final report = (res.stdout as String).trim();
          if (report.isNotEmpty) {
            stdout.writeln(report
                .split('\n')
                .map((l) => '      $l')
                .join('\n'));
          }
        }
        final cells =
            jsonDecode(File(outPath).readAsStringSync()) as List<dynamic>;
        // --- atomic block (no await until the next loop turn) ---
        results[key] = {
          'flop': s.flop,
          'spr': s.spr,
          // Stamp scenario/profile/dump-rounds so a library rebuild groups each
          // spot under its scenario and folds in ONLY matching-profile spots — a
          // results.json carried over from a different profile (e.g. v1 'multi')
          // must not blend its cells into this library.
          'scenario': kScenario,
          'profile': kBetProfile,
          'dump_rounds': kDumpRounds,
          'exploitability': expl,
          'wall_ms': wallMs,
          'cells': cells,
        };
        _appendResult(key, results[key] as Map<String, dynamic>);
        solved++;
        stdout.writeln('    ✓ [${s.flop} ${s.spr}] ${cells.length} cells · expl '
            '${expl?.toStringAsFixed(2)}% · ${wallMs ~/ 1000}s');
      } catch (e) {
        failed++;
        stdout.writeln('    ✗ [${s.flop} ${s.spr}] $e');
      } finally {
        if (heldGb > 0 || heldThreads > 0) budget.release(heldGb, heldThreads);
        ds?.cleanup(); // remove the dump temp dir (after tabulating, or on failure)
      }
    }
  }

  await Future.wait([for (var w = 0; w < parallel; w++) worker()]);
  sw.stop();
  stdout.writeln('\nGrid: solved $solved, skipped $skipped, failed $failed '
      'in ${sw.elapsed.inMinutes}m.');

  if (results.isNotEmpty) _writeLibrary(results);
}
