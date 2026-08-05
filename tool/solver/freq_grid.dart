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
//     a box — the launcher scp's the single results file). BULK-CAMPAIGN NOTE:
//     during a full-density campaign do NOT compact — the monolith stays frozen
//     and the per-scenario shards are the durable store (_loadResults folds
//     shards over the monolith in memory, so dry-runs and --write never need a
//     compaction; a 26k-spot monolith would be ~12 GB and poison every box seed).
//   … --no-write                                     # skip the end-of-run
//     library assembly — REQUIRED on bulk boxes: a box seeded with only its own
//     scenario's cache would trip _writeLibrary's scenario-drop guard (and a
//     partial write must never be pulled over the shipped asset). The one
//     authoritative --write happens operator-side from the union of all shards.
//   TLSOLVE_SPRS=deep dart run …                     # solve ONLY the named SPR
//     bucket(s) (comma list; names must exist in the scenario's sprReps —
//     unknown names fail fast). Contingency knob for the class-split: deep-only
//     cleanup passes, or pairing a small-RAM box (TLSOLVE_MAX_SPOT_GB) with a
//     big-RAM deep-only box.
//   … --emit-pack <dir>                             # ALSO write a GTO Explorer
//     pack per solved spot to <dir>/<scenario>/<flop>_<spr>/ (same parse pass —
//     see explorer_pack.dart / launch/GTO_EXPLORER.md). Works with BOTH dump
//     formats since the TLSD pack port (2026-08-05). Only NEWLY-SOLVED spots
//     get packs: a cached spot is skipped entirely — pair with --ignore-cache
//     to re-solve library-cached spots for pack emission (the run warns when
//     cached spots are silently packless).
//   … --ignore-cache                                # solve every grid spot even
//     if its key is already in the results shards (pack fleet runs: the density
//     campaign cached all 26,325 library spots, but packs need fresh solves).
//     Pair with --no-write so re-solves never touch the shipped library.

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

/// Keys-only cache load for paths that never assemble the library (bulk
/// `--no-write` runs and `--sched-dry-run`): `_isCached` needs only KEY
/// presence, and full per-cell entries for a density scenario decode to tens
/// of GB — an OOM on the 32 GB operator machine (the end-of-stage zero-pending
/// check) and wasted RAM on boxes. The monolith is decoded once for its keys
/// (values become garbage immediately); shards are STREAMED line-by-line, and
/// only the CURRENT scenario's shard is read — spot keys embed the scenario,
/// so other scenarios' (multi-GB by mid-campaign) shards can never satisfy a
/// cache probe here.
Future<Set<String>> _loadCachedKeys() async {
  final keys = <String>{};
  final f = File(kResultsPath);
  if (f.existsSync()) {
    keys.addAll(
        (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).keys);
  }
  final shard = File(_shardPath());
  if (shard.existsSync()) {
    final lines = shard
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) continue;
      try {
        keys.add((jsonDecode(l) as Map<String, dynamic>)['key'] as String);
      } catch (e) {
        stderr.writeln('WARN: skipping bad shard line in ${shard.path}: $e');
      }
    }
  }
  return keys;
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
  final noWrite = args.contains('--no-write');
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

  // Keys-only mode: bulk boxes (--no-write) and --sched-dry-run never
  // assemble the library, so they need cache-KEY presence only — loading the
  // decoded entries would be tens of GB at density-campaign shard sizes.
  final schedDryRun = args.contains('--sched-dry-run');
  final keysOnly = (noWrite || schedDryRun) && !writeOnly;
  final results = keysOnly ? <String, dynamic>{} : _loadResults();
  final cachedKeys = keysOnly ? await _loadCachedKeys() : null;
  bool isCachedSpot(String flop, String spr) => cachedKeys != null
      ? (cachedKeys.contains(_spotKey(flop, spr)) ||
          (kScenario == 'srp_late_v_bb' &&
              cachedKeys.contains(_legacySpotKey(flop, spr))))
      : _isCached(results, flop, spr);

  if (writeOnly) {
    _writeLibrary(results);
    return;
  }

  final ranges = scenarioRanges();
  final gridFlops = _gridFlops();
  // TLSOLVE_SPRS: optional include-filter on SPR bucket names. Bucket sets
  // differ per scenario (3bp has committed/shallow/medium, no deep), so an
  // unknown name is a hard error — a typo'd filter must fail fast, not
  // silently solve zero spots. Throws StateError on a bad name.
  final Set<String>? sprFilter;
  try {
    sprFilter = parseSprFilter(
        Platform.environment['TLSOLVE_SPRS'], kSprReps.keys);
  } on StateError catch (e) {
    stderr.writeln('TLSOLVE_SPRS: $e');
    exitCode = 64;
    return;
  }
  final sprEntries = kSprReps.entries
      .where((e) => sprFilter == null || sprFilter.contains(e.key))
      .toList();
  stdout.writeln('flop source: ${_flopSourceLabel()} (${gridFlops.length} '
      'flops × ${sprEntries.length} SPRs'
      '${sprFilter == null ? '' : ' — TLSOLVE_SPRS=${sprFilter.join(',')}'})');
  final spots = <({String flop, String spr, double sprVal})>[];
  for (final flop in gridFlops) {
    for (final e in sprEntries) {
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
  // Pack emission works on BOTH dump formats since the TLSD pack port
  // (explorer_pack walks DumpNodeView; tabulate_one runs a second streaming
  // pass for the pack) — TLSD is the economic default for pack fleets.
  // The effective format of THIS run's dumps — drives the parse footprints
  // (JSON parses need the giant heap; TLSD a few GB).
  final dumpFmtEnv = solverDumpFmt();
  // Whether tabulate_one will EAGERLY materialize its input: true for any
  // JSON dump (TLSOLVE_DUMP_FMT=json/both — with 'both' the dump handed to
  // tabulate_one is the JSON file) and for the eager TLSD rollback. Drives
  // BOTH the subprocess heap default and the parse-phase RAM
  // claims (spotFootprint) — a streaming tabulate claiming the eager
  // footprint would starve solve admissions for nothing.
  final eagerTabulate =
      Platform.environment['TLSOLVE_TABULATE_EAGER'] == '1' ||
          dumpFmtEnv != 'bin';

  // Spots still needing a solve (cached ones skipped), capped to --limit if set.
  // Each pending spot is claimed and solved exactly once by exactly one worker.
  // TLSOLVE_MAX_SPOT_GB skips (never fails) spots whose predicted solve RAM
  // exceeds it — a small-RAM box grinds the shallow/medium classes while a big
  // box takes deep (the split is pure env policy; see spot_sched.dart).
  final maxSpotGb =
      double.tryParse(Platform.environment['TLSOLVE_MAX_SPOT_GB'] ?? '');
  final ignoreCache = args.contains('--ignore-cache');
  if (ignoreCache) {
    stdout.writeln('--ignore-cache: results-shard cache keys are IGNORED — '
        'every grid spot solves fresh (library-cached spots included). '
        '${noWrite ? '' : '⚠ without --no-write these re-solves would '
            'rewrite library entries — pack fleets should pass --no-write.'}');
  }
  final pending = <({String flop, String spr, double sprVal})>[];
  var skipped = 0, skippedTooBig = 0;
  for (final s in spots) {
    if (!ignoreCache && isCachedSpot(s.flop, s.spr)) {
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
        '(only newly-solved spots do) — pass --ignore-cache (with --no-write) '
        'to re-solve them with pack emission.');
  }

  // PIPELINE (tabulate-decoupling, stage-1 lesson): each worker drains the
  // shared queue, but a worker lane only ever waits on SOLVES — when a solve
  // finishes, the worker acquires the parse claim + a tabulate slot, FIRES the
  // tabulate as a detached (tracked, unawaited) future, and immediately loops
  // to the next spot. Stage 1 measured deep tabulates at 20-40 min under
  // saturation; with the old solve→await-tabulate lane coupling most lanes sat
  // in tabulate and only 4-7 of 24 were solving. Backpressure is real but
  // gentle: the parse claim comes from the SAME budget (RAM/threads), and
  // `tabSlots` (TLSOLVE_MAX_PENDING_TABULATES, default 16) bounds FIRED
  // detached tabulates. The true /dev/shm dump residency bound is
  // maxPendingTabs + parallel: a lane that finished its solve holds its dump
  // while it waits at tabSlots.acquire(), and a solving lane's dump is being
  // written — so size /dev/shm for (16 + parallel) × ~1.5 GB deep dumps, not
  // 16. Setting it to 1 approximates the old serialized behavior — the soft
  // rollback for the decoupling.
  //
  // Crash-loss window (spot reclaim / box death): completed solves whose
  // tabulate hasn't landed in the shard yet — up to maxPendingTabs fired +
  // parallel waiting — are lost with the tmpfs and re-solve on relaunch. The
  // default 16 keeps that comparable to the ≤20-min periodic-sync loss the
  // bulk runbook already accepts; raise it only with that trade-off in mind.
  //
  // Concurrency safety is unchanged in kind: the tabulate subprocess is a
  // separate PROCESS (never Isolate.run — the shared-GC lesson, see
  // VCPU_RUNBOOK), and the results-mutate + _appendResult block in the
  // completion handler runs WITHOUT an await, so it stays atomic on the main
  // isolate: no shard-file race, no concurrent map modification. ✓/✗ lines can
  // now print after later '[n/total] solving' lines (completion is async);
  // end-of-run counts are settled by awaiting workers AND outstanding
  // tabulates before the summary/marker.
  //
  // Streaming tabulator note: TLSOLVE_TABULATE_HEAP_MB defaults to 16 GB (the
  // streaming cursor retains raw bytes + O(depth)) ONLY when the tabulate will
  // actually stream — i.e. the dump handed to tabulate_one is TLSD
  // (dumpFmtEnv == 'bin') and the eager rollback isn't engaged. JSON dumps
  // (--emit-pack forces JSON; TLSOLVE_DUMP_FMT=json/both hands tabulate_one
  // the JSON file) still eagerly jsonDecode multi-GB trees (~45 GB medium /
  // ~150 GB deep), as does TLSOLVE_TABULATE_EAGER=1 — both keep the 80 GB
  // default (a 16 GB cap there OOMs every subprocess and destroys the run's
  // paid solves). `eagerTabulate` is derived next to dumpFmtEnv above.
  final tabHeapMb =
      int.tryParse(Platform.environment['TLSOLVE_TABULATE_HEAP_MB'] ?? '') ??
          (eagerTabulate ? 80000 : 16000);
  // Clamp ≥1: Semaphore(0) can never be acquired (release only ever follows a
  // successful acquire), so 0 — a plausible misreading as "disable pending
  // tabulates" — would silently hang every lane after its first solve on a
  // billing cloud box. 1 is the real serialization floor.
  var maxPendingTabs = int.tryParse(
          Platform.environment['TLSOLVE_MAX_PENDING_TABULATES'] ?? '') ??
      16;
  if (maxPendingTabs < 1) maxPendingTabs = 1;
  final tabSlots = Semaphore(maxPendingTabs);
  final outstanding = <Future<void>>[];

  // Detached per-spot tabulate + record. NEVER throws (fully self-handled);
  // owns the parse claim, the tabulate slot, and the dump dir, releasing all
  // three in `finally`.
  Future<void> tabulateAndRecord(
    ({String flop, String spr, double sprVal}) s,
    String key,
    SpotFootprint fp,
    DumpSolve ds,
    double pot0,
    double effStack,
    int maxLen,
    String? packDir,
  ) async {
    try {
      final outPath = '${ds.dumpPath}.cells.json';
      final res = await Process.run(Platform.resolvedExecutable, [
        '--old_gen_heap_size=$tabHeapMb',
        'run',
        'tool/solver/tabulate_one.dart',
        ds.dumpPath,
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
          stdout.writeln(report.split('\n').map((l) => '      $l').join('\n'));
        }
      }
      final cells =
          jsonDecode(File(outPath).readAsStringSync()) as List<dynamic>;
      // --- atomic block (no await from here to the ✓ line) ---
      final entry = <String, dynamic>{
        'flop': s.flop,
        'spr': s.spr,
        // Stamp scenario/profile/dump-rounds so a library rebuild groups each
        // spot under its scenario and folds in ONLY matching-profile spots — a
        // results.json carried over from a different profile (e.g. v1 'multi')
        // must not blend its cells into this library.
        'scenario': kScenario,
        'profile': kBetProfile,
        'dump_rounds': kDumpRounds,
        'exploitability': ds.exploitability,
        'wall_ms': ds.wallMs,
        'cells': cells,
      };
      // In keys-only (bulk) mode the map is never used for a library write —
      // holding every solved entry would just accumulate the slice's cells
      // in RAM for nothing. The shard append is the record either way.
      if (!keysOnly) results[key] = entry;
      _appendResult(key, entry);
      solved++;
      stdout.writeln('    ✓ [${s.flop} ${s.spr}] ${cells.length} cells · expl '
          '${ds.exploitability?.toStringAsFixed(2)}% · ${ds.wallMs ~/ 1000}s');
    } catch (e) {
      failed++;
      stdout.writeln('    ✗ [${s.flop} ${s.spr}] $e');
    } finally {
      budget.release(fp.parseGb, 1);
      tabSlots.release();
      ds.cleanup(); // the dump must outlive its tabulate — cleaned only here
    }
  }

  Future<void> worker() async {
    while (true) {
      final i = next;
      if (i >= total) break;
      next++;
      final s = pending[i];
      final key = _spotKey(s.flop, s.spr);
      final fp = spotFootprint(s.sprVal,
          dumpFmt: dumpFmtEnv, eagerTabulate: eagerTabulate);
      DumpSolve? ds;
      // Phase claims: solve holds (solveGb, solver threads); the detached
      // tabulate holds (parseGb, 1 thread). Track what THIS lane holds so the
      // finally releases exactly once whatever phase failed; once the handler
      // is fired, claim + slot + dump ownership transfer to it.
      var heldGb = 0.0;
      var heldThreads = 0;
      var heldTabSlot = false;
      try {
        await budget.acquire(fp.solveGb, solverThreads);
        heldGb = fp.solveGb;
        heldThreads = solverThreads;
        final n = ++started;
        stdout.writeln('[$n/$total] solving ${s.flop} SPR ${s.spr} '
            '(${fp.solveGb.toStringAsFixed(0)} GB claim) …');
        final spot = gridSpot(s.flop, s.sprVal, ranges.ip, ranges.oop);
        // Dump format follows TLSOLVE_DUMP_FMT/its default for pack and
        // non-pack runs alike (the TLSD pack port removed the JSON coupling).
        ds = await solveToFile(spot,
            dumpRounds: kDumpRounds, betProfile: kBetProfile);
        // Solve finished — swap this lane down to the tabulate's claim (slot
        // first: it's the cheap resource and keeps acquire order uniform
        // across workers, so the two gates can't deadlock).
        budget.release(heldGb, heldThreads);
        heldGb = 0;
        heldThreads = 0;
        await tabSlots.acquire();
        heldTabSlot = true;
        await budget.acquire(fp.parseGb, 1);
        heldGb = fp.parseGb;
        heldThreads = 1;
        // pot is fixed at 10 in gridSpot; effStack = spr·pot; the tabulator
        // re-derives the SPR bucket per street (flop vs the shallower
        // turn/river after chips go in). dr2 → maxBoardLen 4; dr3 → 5.
        final packDir = emitPackRoot == null
            ? null
            : '$emitPackRoot/$kScenario/'
                '${s.flop.replaceAll(' ', '')}_${s.spr}';
        // FIRE the tabulate detached and move on — ownership of the parse
        // claim, the tabulate slot, and the dump dir transfers to the handler.
        outstanding.add(tabulateAndRecord(s, key, fp, ds, spot.pot.toDouble(),
            spot.effStack.toDouble(), kDumpRounds + 2, packDir));
        ds = null;
        heldGb = 0;
        heldThreads = 0;
        heldTabSlot = false;
      } catch (e) {
        failed++;
        stdout.writeln('    ✗ [${s.flop} ${s.spr}] $e');
      } finally {
        if (heldGb > 0 || heldThreads > 0) budget.release(heldGb, heldThreads);
        if (heldTabSlot) tabSlots.release();
        ds?.cleanup(); // solve-phase failure only — success path transferred
      }
    }
  }

  await Future.wait([for (var w = 0; w < parallel; w++) worker()]);
  // Every worker has fired its last tabulate before returning, so the list is
  // complete — drain it before the summary/marker so counts are final.
  stdout.writeln('… all solves dispatched; draining outstanding tabulates.');
  await Future.wait(outstanding);
  sw.stop();
  stdout.writeln('\nGrid: solved $solved, skipped $skipped, failed $failed '
      'in ${sw.elapsed.inMinutes}m.');

  if (noWrite) {
    if (solved == 0 && failed > 0) {
      // Every attempted spot failed — do NOT print the completion marker.
      // The launcher's bulk health check keys on it; an all-failed slice must
      // read as a FAILED scenario (box left up for triage), never as 'Done'.
      stderr.writeln('bulk run FAILED: 0 solved, $failed failed — '
          'completion marker withheld.');
      exitCode = 1;
    } else {
      stdout.writeln('library write SKIPPED (--no-write): assemble '
          'operator-side from the union of all shards via --write.');
    }
  } else if (results.isNotEmpty) {
    _writeLibrary(results);
  }
}
