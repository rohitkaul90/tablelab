// Curate a balanced benchmark of PHH spots for the eval harness.
//
// Scans a Pluribus PHH corpus, classifies each hand's final board texture, and
// selects a quota'd, deterministic set across the card-logic STRESS categories
// (paired/tripled boards → boat temptation; 3+ suited → flush temptation;
// straight-completing boards → invented/denied straights) plus a small
// solver-checkable set (preflop all-ins). It copies the chosen `.phh` files into
// tool/eval/samples/pluribus/ and writes a spots.json the baker consumes.
//
// Hero = a player with KNOWN hole cards who never folded (reached the final
// board), so every selected spot has real postflop streets to score.
//
//   dart run tool/eval/curate.dart <corpusDir> <count> [spotsOut] [sampleDir]
//
// e.g. dart run tool/eval/curate.dart /tmp/phh/phh-dataset/data/pluribus 30

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';

import 'phh_parser.dart';

/// Texture category used to balance the benchmark.
enum Texture { paired, flush, straight, dry }

class Candidate {
  final String file; // absolute corpus path
  final String game; // pluribus game id (dir)
  final String hand; // hand id (file stem)
  final int hero; // 1-based p-index
  final Texture texture;
  final List<String> board;
  final bool preflopAllIn;
  Candidate(this.file, this.game, this.hand, this.hero, this.texture,
      this.board, this.preflopAllIn);
}

const _suitChars = 'cdhs';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/eval/curate.dart <corpusDir> <count> '
        '[spotsOut] [sampleDir]');
    exit(2);
  }
  final corpusDir = args[0];
  final count = args.length > 1 ? int.parse(args[1]) : 30;
  final spotsOut = args.length > 2 ? args[2] : 'tool/eval/spots.json';
  final sampleDir = args.length > 3 ? args[3] : 'tool/eval/samples/pluribus';

  final files = Directory(corpusDir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.phh'))
      .map((f) => f.path)
      .toList()
    ..sort(_naturalCompare);
  stderr.writeln('scanning ${files.length} hands in $corpusDir');

  // Quotas: weight toward the hallucination-prone textures.
  final quotas = <String, int>{
    'flush': (count * 0.30).round(),
    'paired': (count * 0.30).round(),
    'straight': (count * 0.25).round(),
    'solver': (count * 0.10).round(),
    'dry': (count * 0.05).round(),
  };
  final picked = <String, List<Candidate>>{
    for (final k in quotas.keys) k: [],
  };
  bool full() => quotas.keys.every((k) => picked[k]!.length >= quotas[k]!);

  // Spread selection across games (avoid clustering in one Pluribus session) by
  // striding through the sorted file list.
  final stride = (files.length / (count * 12)).clamp(1, 997).floor();
  var scanned = 0;
  for (var i = 0; i < files.length && !full(); i += stride) {
    scanned++;
    final cand = _classify(files[i]);
    if (cand == null) continue;
    final bucket = cand.preflopAllIn ? 'solver' : cand.texture.name;
    final list = picked[bucket];
    if (list == null || list.length >= quotas[bucket]!) continue;
    list.add(cand);
  }

  Directory(sampleDir).createSync(recursive: true);
  final spots = <Map<String, dynamic>>[];
  for (final entry in picked.entries) {
    for (final c in entry.value) {
      final stem = 'pluribus-${c.game}-${c.hand}';
      final destName = '$stem.phh';
      File(c.file).copySync('$sampleDir/$destName');
      spots.add({
        'id': '$stem-p${c.hero}',
        'file': '$sampleDir/$destName',
        'source': 'pluribus/${c.game}/${c.hand}',
        'hero': c.hero,
        'bucket': entry.key == 'solver' ? 'solver-checkable' : 'card-logic',
        'notes': '${entry.key} board ${c.board.join(" ")}'
            '${c.preflopAllIn ? " (preflop all-in)" : ""}',
        'reads': <dynamic>[],
      });
    }
  }
  spots.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

  File(spotsOut)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(spots));

  stderr.writeln('scanned $scanned (stride $stride), selected ${spots.length}:');
  for (final k in quotas.keys) {
    stderr.writeln('  $k: ${picked[k]!.length}/${quotas[k]}');
  }
  stderr.writeln('-> $spotsOut  (+ ${spots.length} .phh in $sampleDir)');
}

/// Parse + classify a hand. Returns null when it isn't a usable card-logic spot
/// (no postflop board, no surviving known-cards hero, or a parse error).
Candidate? _classify(String path) {
  final PhhHand phh;
  try {
    phh = parsePhhText(File(path).readAsStringSync());
  } catch (_) {
    return null;
  }

  // Final board from all `d db` deals.
  final board = <String>[];
  var folds = <int>{};
  for (final t in phh.actionTokens) {
    final tt = t.trim();
    if (tt.startsWith('d db ')) {
      board.addAll(_splitBoard(tt.substring(5).trim()));
    }
    final f = RegExp(r'^p(\d+) f$').firstMatch(tt);
    if (f != null) folds.add(int.parse(f.group(1)!));
  }
  if (board.length < 3) return null; // need a flop+ to have board texture

  // Hero = lowest-index player with known cards who never folded.
  final survivors = phh.knownHolePlayers.difference(folds).toList()..sort();
  if (survivors.isEmpty) return null;
  final hero = survivors.first;

  // >3 board deals (run-it-twice) can't be represented; the baker skips these,
  // so don't select them.
  final boardDeals =
      phh.actionTokens.where((t) => t.trim().startsWith('d db ')).length;
  if (boardDeals > 3) return null;

  final texture = _texture(board);
  final preflopAllIn = _hasPreflopAllIn(phh);
  return Candidate(path, _gameOf(path), _handOf(path), hero, texture, board,
      preflopAllIn);
}

Texture _texture(List<String> board) {
  final ranks = board.map((c) => cardRank(parseCard(c))).toList();
  final suits = board.map((c) => cardSuit(parseCard(c))).toList();

  final rankCount = <int, int>{};
  for (final r in ranks) {
    rankCount[r] = (rankCount[r] ?? 0) + 1;
  }
  if (rankCount.values.any((n) => n >= 2)) return Texture.paired;

  final suitCount = <int, int>{};
  for (final s in suits) {
    suitCount[s] = (suitCount[s] ?? 0) + 1;
  }
  if (suitCount.values.any((n) => n >= 3)) return Texture.flush;

  // Straight-y: any 5-rank window the board supplies >=3 of.
  final present = <int>{};
  for (final r in ranks) {
    final v = r + 2;
    present.add(v);
    if (v == 14) present.add(1);
  }
  for (var low = 1; low <= 10; low++) {
    var on = 0;
    for (var v = low; v < low + 5; v++) {
      if (present.contains(v)) on++;
    }
    if (on >= 3) return Texture.straight;
  }
  return Texture.dry;
}

/// A preflop shove-and-call: a `cbr` for a player's full stack before any board
/// deal, with at least one subsequent `cc`.
bool _hasPreflopAllIn(PhhHand phh) {
  final stacks = phh.startingStacks;
  var calledAfter = false;
  var shove = false;
  for (final t in phh.actionTokens) {
    final tt = t.trim();
    if (tt.startsWith('d db ')) break; // preflop only
    final cbr = RegExp(r'^p(\d+) cbr (\d+)$').firstMatch(tt);
    if (cbr != null) {
      final seat = int.parse(cbr.group(1)!) - 1;
      final to = int.parse(cbr.group(2)!);
      if (seat < stacks.length && to >= stacks[seat]) shove = true;
    }
    if (shove && tt.endsWith(' cc')) calledAfter = true;
  }
  return shove && calledAfter;
}

List<String> _splitBoard(String s) {
  final out = <String>[];
  for (var i = 0; i + 1 < s.length; i += 2) {
    final c = s.substring(i, i + 2);
    if (_suitChars.contains(c[1])) out.add(c);
  }
  return out;
}

String _gameOf(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.length >= 2 ? parts[parts.length - 2] : 'g';
}

String _handOf(String path) =>
    path.replaceAll('\\', '/').split('/').last.replaceAll('.phh', '');

// Sort "100/2.phh" before "100/10.phh" (numeric-aware on the trailing number).
int _naturalCompare(String a, String b) {
  int numOf(String p) =>
      int.tryParse(_handOf(p)) ?? 0;
  final ga = _gameOf(a), gb = _gameOf(b);
  final gc = (int.tryParse(ga) ?? 0).compareTo(int.tryParse(gb) ?? 0);
  return gc != 0 ? gc : numOf(a).compareTo(numOf(b));
}
