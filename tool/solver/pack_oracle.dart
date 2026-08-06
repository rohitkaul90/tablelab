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
import 'dart:typed_data';

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
  final keepDump = args.remove('--keep-dump');
  if (args.length < 2) {
    stderr.writeln('usage: pack_oracle --solve "<flop>" <sprName> '
        '[--keep-dump]');
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
    if (keepDump) {
      stdout.writeln('kept dumps: ${solve.dumpPath} (json) + '
          '${solve.dumpPath}.tlsd (bin) — delete the directory when done.');
    } else {
      solve.cleanup();
    }
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
    if (root == null || !root.isAction) {
      // exitCode + return (NOT exit()) so the finally still cleans the temp
      // dir — the JSON pack (potentially hundreds of MB) is already on disk.
      stderr.writeln('pack_oracle: TLSD dump root is not an action node');
      exitCode = 1;
      return;
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

    // Comparison. Byte equality is the fast path, but on REAL dumps the two
    // sources differ at the wire: the C++ TLSD writer quantizes freqs to u16
    // (1/65535) while the JSON dump carries full doubles — so values that
    // straddle the pack's own coarser quantization boundaries (freq u8×250,
    // reach u16, ev i16×20) legally differ by ONE unit, and combos exactly at
    // kReachEpsilon may flip membership. Same class the WS1c library gate
    // accepted with its mass-aware tolerance. The oracle therefore decodes
    // both packs and enforces: identical structure (chunks, node paths,
    // actions, chip state), ≤1-quantization-unit value deviations, and
    // ε-boundary-only membership flips.
    final a = _files('${work.path}/json');
    final b = _files('${work.path}/tlsd');
    final allKeys = {...a.keys, ...b.keys}.toList()..sort();
    var byteIdentical = 0, tolerated = 0, hardDiffs = 0;
    var maxFreqU = 0, maxReachU = 0, maxEqU = 0, maxEvU = 0;
    var epsilonFlips = 0, naStraddles = 0, combosCompared = 0;
    final eqOffenders = <({
      String chunk,
      String path,
      int comboId,
      double reach,
      double? eqA,
      double? eqB,
      int units,
    })>[];
    for (final k in allKeys) {
      final fa = a[k], fb = b[k];
      if (fa == null || fb == null) {
        stdout.writeln('  ✗ $k: only in ${fa == null ? 'TLSD' : 'JSON'} pack');
        hardDiffs++;
        continue;
      }
      final ba = File(fa).readAsBytesSync();
      final bb = File(fb).readAsBytesSync();
      if (_bytesEqual(ba, bb)) {
        byteIdentical++;
        continue;
      }
      if (k == 'manifest.json') {
        // Manifests differ iff chunk raw/gz sizes differ (tolerated below);
        // combo lists + spot meta must match.
        final ma = jsonDecode(utf8.decode(ba)) as Map<String, dynamic>;
        final mb = jsonDecode(utf8.decode(bb)) as Map<String, dynamic>;
        final comboA = jsonEncode(ma['combos']);
        final comboB = jsonEncode(mb['combos']);
        if (comboA != comboB) {
          stdout.writeln('  ✗ manifest combo lists differ');
          hardDiffs++;
        } else {
          tolerated++;
        }
        continue;
      }
      // Decoded chunk comparison.
      final na = decodeChunk(Uint8List.fromList(gzip.decode(ba)));
      final nb = decodeChunk(Uint8List.fromList(gzip.decode(bb)));
      var chunkBad = false;
      if (na.length != nb.length) {
        stdout.writeln('  ✗ $k: ${na.length} vs ${nb.length} nodes');
        hardDiffs++;
        continue;
      }
      for (var n = 0; n < na.length && !chunkBad; n++) {
        final x = na[n], y = nb[n];
        if (x.path != y.path ||
            x.street != y.street ||
            x.actorIsOop != y.actorIsOop ||
            x.potBefore != y.potBefore ||
            x.toCall != y.toCall ||
            x.behind != y.behind ||
            x.actions.join('|') != y.actions.join('|')) {
          stdout.writeln('  ✗ $k node $n (${x.path}): structural/chip-state '
              'mismatch');
          chunkBad = true;
          break;
        }
        final byIdA = {for (final c in x.combos) c.comboId: c};
        final byIdB = {for (final c in y.combos) c.comboId: c};
        for (final id in {...byIdA.keys, ...byIdB.keys}) {
          final ca = byIdA[id], cb = byIdB[id];
          if (ca == null || cb == null) {
            // Membership flip: legal only in a TIGHT band around the reach-ε
            // boundary — u16 freq quantization moves reach by ≲4/65535, so a
            // legitimate flip's surviving reach sits within that of ε (plus
            // margin). A loose `< 2ε` band became ~80× wider than the physics
            // when ε rose to 5e-3 (review finding) and would have hidden real
            // membership bugs on combos with up to 2× threshold reach.
            final present = ca ?? cb!;
            if ((present.reach - kReachEpsilon).abs() <= 6 / 65535) {
              epsilonFlips++;
              continue;
            }
            stdout.writeln('  ✗ $k node $n (${x.path}) combo $id: present in '
                'only one pack at reach ${present.reach.toStringAsFixed(6)}');
            chunkBad = true;
            break;
          }
          combosCompared++;
          final reachU = ((ca.reach - cb.reach).abs() * 65535).round();
          if (reachU > maxReachU) maxReachU = reachU;
          // Equity: NA-vs-value = a node whose opponent mass straddles
          // kOppMassFloor across dump formats (quantization moves the sum a
          // hair over/under). Counted, not failed — the mass there is ~floor,
          // i.e. the equity is borderline-meaningless on both sides.
          final int eqU;
          if (ca.equity == null || cb.equity == null) {
            if (ca.equity != cb.equity) naStraddles++;
            eqU = 0;
          } else {
            eqU = ((ca.equity! - cb.equity!).abs() * 250).round();
          }
          if (eqU > 5) {
            eqOffenders.add((
              chunk: k,
              path: x.path,
              comboId: id,
              reach: ca.reach,
              eqA: ca.equity,
              eqB: cb.equity,
              units: eqU,
            ));
          }
          if (eqU > maxEqU) maxEqU = eqU;
          final pasU = ca.evPassive == null || cb.evPassive == null
              ? (ca.evPassive == cb.evPassive ? 0 : 999)
              : ((ca.evPassive! - cb.evPassive!).abs() * 20).round();
          if (pasU > maxEvU) maxEvU = pasU;
          for (var ai = 0; ai < ca.freqs.length; ai++) {
            final fU = ((ca.freqs[ai] - cb.freqs[ai]).abs() * 250).round();
            if (fU > maxFreqU) maxFreqU = fU;
            final ea = ca.evs[ai], eb = cb.evs[ai];
            final eU = ea == null || eb == null
                ? (ea == eb ? 0 : 999)
                : ((ea - eb).abs() * 20).round();
            if (eU > maxEvU) maxEvU = eU;
          }
        }
      }
      if (chunkBad) {
        hardDiffs++;
      } else {
        tolerated++;
      }
    }
    // Reach is a PRODUCT of quantized freqs down the line (u16 error ≈7.6e-6
    // per factor, ~4-6 factors by the river) — allow 4 u16 units. Equity is a
    // weighted mean over the (pruned, floor-gated) opponent range — weight
    // quantization can move it a few u8 units near the mass floor; 5 units
    // (2%) still catches real logic bugs, which measure 50-150 units. NA
    // straddles must stay a trace fraction of compared combos.
    final withinTol = maxFreqU <= 1 &&
        maxReachU <= 4 &&
        maxEqU <= 5 &&
        maxEvU <= 1 &&
        naStraddles <= combosCompared * 0.005;
    stdout.writeln('files: $byteIdentical byte-identical · $tolerated '
        'decoded-equal within quantization tolerance · $hardDiffs hard diffs');
    stdout.writeln('max deviations (quant units): freq $maxFreqU/1 · reach '
        '$maxReachU/4 · equity $maxEqU/5 · ev $maxEvU/1 · ε-boundary combo '
        'flips $epsilonFlips · NA straddles $naStraddles/'
        '${(combosCompared * 0.005).round()} (of $combosCompared compared)');
    if (eqOffenders.isNotEmpty) {
      eqOffenders.sort((a, b) => b.units.compareTo(a.units));
      stdout.writeln('equity offenders (>5 units): ${eqOffenders.length} '
          'combo(s); top 10 by deviation:');
      for (final o in eqOffenders.take(10)) {
        stdout.writeln('  ${o.chunk} [${o.path}] combo ${o.comboId}: '
            'reach ${o.reach.toStringAsFixed(6)}, '
            'eq ${o.eqA?.toStringAsFixed(4)} vs ${o.eqB?.toStringAsFixed(4)} '
            '(${o.units}u)');
      }
      final lowReach = eqOffenders.where((o) => o.reach < 0.01).length;
      stdout.writeln('  … $lowReach/${eqOffenders.length} offenders have '
          'acting reach < 0.01');
    }
    if (hardDiffs == 0 && withinTol) {
      stdout.writeln('PACK ORACLE PASS: TLSD pack is quantization-equivalent '
          'to the JSON pack (${allKeys.length} files).');
    } else {
      stdout.writeln('PACK ORACLE FAIL.');
      exitCode = 1;
    }
  } finally {
    work.deleteSync(recursive: true);
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Map<String, String> _files(String root) {
  final out = <String, String>{};
  for (final f in Directory(root).listSync(recursive: true)) {
    if (f is! File) continue;
    out[f.path.substring(root.length + 1).replaceAll('\\', '/')] = f.path;
  }
  return out;
}
