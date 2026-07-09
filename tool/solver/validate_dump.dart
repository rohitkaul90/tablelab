// TLSD ⇄ JSON dual-dump equivalence harness (WS1c of the full-density plan).
//
// Feeds the SAME converged solve's JSON dump and TLSD binary dump through the
// tabulator and asserts the resulting library cells agree:
//   - identical cell KEY sets (texture/spr/street/position/facing/hand-class)
//   - per-cell |freq diff| ≤ 0.001 (the u16 quantization bound, ε≈1.5e-5,
//     compounded through reach products — see the TLSD format notes)
//   - per-cell |reachWeight diff| ≤ 0.1% relative OR ≤ 0.001 absolute mass —
//     the absolute escape covers near-zero-mass cells where a deep line's
//     compounded quantization error is relatively large but 4 orders of
//     magnitude below the library's 8.0 eligibility threshold (observed:
//     0.108% rel on a 0.045-mass turn facing_raise cell)
//
// Produce the input pair with one solve via TLSOLVE_DUMP_FMT=both (the solver
// emits dump.json + dump.json.tlsd from one converged strategy), or pass any
// two paths explicitly.
//
// Usage (pre-existing dump pair):
//   dart run tool/solver/validate_dump.dart <dump.json> <dump.tlsd> \
//       <flop e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen>
//
// Usage (solve-then-validate — one REAL grid spot through the whole pipeline;
// scenario/profile/threads from the usual TLSOLVE_* env; REQUIRES
// TLSOLVE_DUMP_FMT=both so the solver emits both dumps from one strategy):
//   TLSOLVE_SCENARIO=3bp_bb_v_btn TLSOLVE_DUMP_FMT=both TLSOLVE_THREADS=8 \
//     dart run tool/solver/validate_dump.dart --solve "Ks 9h 4c" committed
//
// Exit 0 = equivalent; exit 1 = mismatches (printed); exit 64 = bad args.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';

import 'freq_grid.dart';
import 'freq_tabulate.dart';
import 'run_solver.dart';

const _freqTol = 0.001;
const _reachRelTol = 0.001;

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args[0] == '--solve') {
    await _solveAndValidate(args.skip(1).toList());
    return;
  }
  if (args.length < 6) {
    stderr.writeln('usage: validate_dump <dump.json> <dump.tlsd> '
        '<flop e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen>\n'
        '   or: validate_dump --solve "<flop e.g. Ks 9h 4c>" <sprName>');
    exit(64);
  }
  final flop = <int>[];
  for (var i = 0; i + 1 < args[2].length; i += 2) {
    final c = parseCard(args[2].substring(i, i + 2));
    if (c >= 0) flop.add(c);
  }
  final pot0 = double.tryParse(args[3]);
  final effStack = double.tryParse(args[4]);
  final maxLen = int.tryParse(args[5]);
  if (flop.length < 3 || pot0 == null || effStack == null || maxLen == null) {
    stderr.writeln('validate_dump: bad args');
    exit(64);
  }
  _comparePair(args[0], args[1],
      board: flop, pot0: pot0, effStack: effStack, maxBoardLen: maxLen);
}

/// Solve ONE grid spot of the env-selected scenario with the dual-dump format
/// and validate the pair — the full-pipeline flavor of the WS1c gate.
Future<void> _solveAndValidate(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: validate_dump --solve "<flop>" <sprName>');
    exit(64);
  }
  if ((Platform.environment['TLSOLVE_DUMP_FMT'] ?? '').toLowerCase() !=
      'both') {
    stderr.writeln('--solve requires TLSOLVE_DUMP_FMT=both '
        '(one solve, two dumps).');
    exit(64);
  }
  final flopStr = args[0];
  final sprName = args[1];
  final sprVal = kSprReps[sprName];
  if (sprVal == null) {
    stderr.writeln('unknown sprName "$sprName" for scenario '
        '(have: ${kSprReps.keys.join('/')})');
    exit(64);
  }
  final ranges = scenarioRanges();
  final spot = gridSpot(flopStr, sprVal, ranges.ip, ranges.oop);
  stdout.writeln('solving $flopStr $sprName (profile $kBetProfile, '
      'dr$kDumpRounds, dual dump)…');
  final solve = await solveToFile(spot,
      dumpRounds: kDumpRounds, betProfile: kBetProfile);
  try {
    stdout.writeln('solved in ${(solve.wallMs / 1000).toStringAsFixed(0)}s '
        '(expl ${solve.exploitability?.toStringAsFixed(2)}%)');
    _comparePair(solve.dumpPath, '${solve.dumpPath}.tlsd',
        board: flopInts(flopStr),
        pot0: 10,
        effStack: sprVal * 10,
        maxBoardLen: kDumpRounds + 2);
  } finally {
    solve.cleanup();
  }
}

void _comparePair(
  String jsonPath,
  String tlsdPath, {
  required List<int> board,
  required double pot0,
  required double effStack,
  required int maxBoardLen,
}) {
  final flop = board;
  final maxLen = maxBoardLen;

  List<FreqCell> tab(String path) => tabulateDumpFile(path,
      board: flop, pot0: pot0, effStack: effStack, maxBoardLen: maxLen);

  stdout.writeln('tabulating JSON  $jsonPath …');
  final swJ = Stopwatch()..start();
  final jsonCells = tab(jsonPath);
  swJ.stop();
  stdout.writeln('tabulating TLSD  $tlsdPath …');
  final swT = Stopwatch()..start();
  final tlsdCells = tab(tlsdPath);
  swT.stop();

  String key(FreqCell c) =>
      '${c.texture}@@${c.sprBucket}@@${c.street}@@${c.position}@@${c.facing}@@${c.handClass}';
  final j = {for (final c in jsonCells) key(c): c};
  final t = {for (final c in tlsdCells) key(c): c};

  var bad = 0;
  void flag(String msg) {
    bad++;
    stderr.writeln('  ✗ $msg');
  }

  for (final k in j.keys) {
    if (!t.containsKey(k)) flag('cell only in JSON: $k');
  }
  for (final k in t.keys) {
    if (!j.containsKey(k)) flag('cell only in TLSD: $k');
  }
  var maxFreqDiff = 0.0, maxReachRel = 0.0;
  for (final k in j.keys) {
    final cj = j[k], ct = t[k];
    if (ct == null) continue;
    final actions = {...cj!.freqs.keys, ...ct.freqs.keys};
    for (final a in actions) {
      final d = ((cj.freqs[a] ?? 0.0) - (ct.freqs[a] ?? 0.0)).abs();
      if (d > maxFreqDiff) maxFreqDiff = d;
      if (d > _freqTol) {
        flag('$k action $a: json=${cj.freqs[a]} tlsd=${ct.freqs[a]} (Δ$d)');
      }
    }
    final base = cj.reachWeight.abs() < 1e-12 ? 1e-12 : cj.reachWeight.abs();
    final abs = (cj.reachWeight - ct.reachWeight).abs();
    final rel = abs / base;
    if (rel > maxReachRel) maxReachRel = rel;
    if (rel > _reachRelTol && abs > 0.001) {
      flag('$k reach: json=${cj.reachWeight} tlsd=${ct.reachWeight} '
          '(rel Δ${(rel * 100).toStringAsFixed(3)}%, abs Δ$abs)');
    }
  }

  final sizeJ = File(jsonPath).lengthSync();
  final sizeT = File(tlsdPath).lengthSync();
  stdout.writeln(jsonEncode({
    'cells_json': jsonCells.length,
    'cells_tlsd': tlsdCells.length,
    'max_freq_diff': double.parse(maxFreqDiff.toStringAsExponential(2)),
    'max_reach_rel_diff': double.parse(maxReachRel.toStringAsExponential(2)),
    'tabulate_ms_json': swJ.elapsedMilliseconds,
    'tabulate_ms_tlsd': swT.elapsedMilliseconds,
    'dump_bytes_json': sizeJ,
    'dump_bytes_tlsd': sizeT,
    'size_ratio': double.parse((sizeJ / sizeT).toStringAsFixed(1)),
    'mismatches': bad,
  }));
  if (bad > 0) {
    stderr.writeln('FAIL: $bad mismatch(es)');
    exit(1);
  }
  stdout.writeln('OK: cells equivalent within tolerance');
}
