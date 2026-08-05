// TLSD pack port — REAL-DUMP byte oracle (the unit-level miniature lives in
// test/solver/dump_codec_test.dart's "cross-format pack oracle" group).
//
// Generates the SAME solved spot's explorer pack twice — once from the JSON
// dump via the original Map-walk path (generatePack), once from the TLSD dump
// via the STREAMING view path tabulate_one uses in the fleet — and compares
// the two output directories file-by-file. Byte-identical output proves the
// port loses nothing on a real solver dump (strategies, EVs, reach, equity,
// chunking, manifests).
//
// Usage (dump pair already on disk, e.g. from validate_dump --solve --keep-dump):
//   dart run tool/solver/pack_oracle.dart <dump.json> <dump.tlsd> \
//       <flopNoSpaces e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen>
//
// Usage (solve-then-compare — one grid spot of the env-selected scenario;
// requires TLSOLVE_DUMP_FMT=both so the solver emits both dumps):
//   set TLSOLVE_DUMP_FMT=both
//   dart run tool/solver/pack_oracle.dart --solve "Ks 9h 4c" shallow
//
// Exit codes: 0 = PASS (identical), 1 = packs differ, 64 = usage.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';

import 'dump_codec.dart';
import 'explorer_pack.dart';
import 'freq_grid.dart';
import 'run_solver.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args[0] == '--solve') {
    await _solveAndCompare(args.skip(1).toList());
    return;
  }
  if (args.length < 6) {
    stderr.writeln('usage: pack_oracle <dump.json> <dump.tlsd> '
        '<flop e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen>\n'
        '   or: pack_oracle --solve "<flop e.g. Ks 9h 4c>" <sprName>');
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
    stderr.writeln('pack_oracle: bad args');
    exit(64);
  }
  _comparePacks(args[0], args[1],
      board: flop, pot0: pot0, effStack: effStack, maxBoardLen: maxLen);
}

Future<void> _solveAndCompare(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: pack_oracle --solve "<flop>" <sprName>');
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
    _comparePacks(solve.dumpPath, '${solve.dumpPath}.tlsd',
        board: flopInts(flopStr),
        pot0: 10,
        effStack: sprVal * 10,
        maxBoardLen: kDumpRounds + 2);
  } finally {
    solve.cleanup();
  }
}

void _comparePacks(
  String jsonPath,
  String tlsdPath, {
  required List<int> board,
  required double pot0,
  required double effStack,
  required int maxBoardLen,
}) {
  final work = Directory.systemTemp.createTempSync('pack_oracle_');
  try {
    // JSON path — the original oracle (Map walk via the wrapper).
    var sw = Stopwatch()..start();
    final jsonRoot =
        jsonDecode(File(jsonPath).readAsStringSync()) as Map<String, dynamic>;
    stdout.writeln('parsed JSON dump in ${sw.elapsedMilliseconds}ms');
    final jr = generatePack(jsonRoot,
        board: board,
        pot0: pot0,
        effStack: effStack,
        scenario: kScenario,
        sprName: 'oracle',
        outDir: '${work.path}/json',
        maxBoardLen: maxBoardLen);
    stdout.writeln('JSON pack: ${jr.stats.chunkCount} chunks, '
        'gz ${(jr.stats.gzBytes / 1048576).toStringAsFixed(1)} MB');

    // TLSD path — the fleet's streaming route (mirrors tabulate_one exactly).
    sw = Stopwatch()..start();
    final dump = readTlsdStreamFile(tlsdPath);
    final root = dump.root;
    if (root == null) {
      stderr.writeln('pack_oracle: TLSD dump has an omitted root');
      exit(1);
    }
    final rootPlayer = root.playerIndex == 1 ? 1 : 0;
    final tr = generatePackFromView(root,
        board: board,
        pot0: pot0,
        effStack: effStack,
        scenario: kScenario,
        sprName: 'oracle',
        outDir: '${work.path}/tlsd',
        maxBoardLen: maxBoardLen,
        ipSeedKeys: dump.dicts[1 - rootPlayer].keys);
    dump.finish();
    stdout.writeln('TLSD pack (streaming): ${tr.stats.chunkCount} chunks, '
        'gz ${(tr.stats.gzBytes / 1048576).toStringAsFixed(1)} MB, '
        '${sw.elapsedMilliseconds}ms total');

    // Byte comparison.
    final a = _files('${work.path}/json');
    final b = _files('${work.path}/tlsd');
    final allKeys = {...a.keys, ...b.keys}.toList()..sort();
    var diffs = 0;
    for (final k in allKeys) {
      final fa = a[k], fb = b[k];
      if (fa == null || fb == null) {
        stdout.writeln('  ✗ $k: only in ${fa == null ? 'TLSD' : 'JSON'} pack');
        diffs++;
        continue;
      }
      final ba = File(fa).readAsBytesSync();
      final bb = File(fb).readAsBytesSync();
      if (ba.length != bb.length) {
        stdout.writeln('  ✗ $k: ${ba.length} vs ${bb.length} bytes');
        diffs++;
        continue;
      }
      for (var i = 0; i < ba.length; i++) {
        if (ba[i] != bb[i]) {
          stdout.writeln('  ✗ $k: first byte diff at offset $i');
          diffs++;
          break;
        }
      }
    }
    if (diffs == 0) {
      stdout.writeln('PACK ORACLE PASS: ${allKeys.length} files '
          'byte-identical across JSON and streaming-TLSD packs.');
    } else {
      stdout.writeln('PACK ORACLE FAIL: $diffs of ${allKeys.length} files '
          'differ.');
      exitCode = 1;
    }
  } finally {
    work.deleteSync(recursive: true);
  }
}

Map<String, String> _files(String root) {
  final out = <String, String>{};
  for (final f in Directory(root).listSync(recursive: true)) {
    if (f is! File) continue;
    out[f.path.substring(root.length + 1).replaceAll('\\', '/')] = f.path;
  }
  return out;
}
