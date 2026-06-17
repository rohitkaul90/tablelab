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

import 'board_texture.dart';
import 'phh_parser.dart';

class Candidate {
  final String file; // absolute corpus path
  final String game; // pluribus game id (dir)
  final String hand; // hand id (file stem)
  final int hero; // 1-based p-index
  final TextureCategory texture;
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
  // Solver (preflop all-ins) is best-effort — deep-stacked Pluribus rarely has
  // them, so an unfillable solver quota must not block completion or force a
  // full-corpus scan. Done when the texture buckets are filled.
  bool full() => quotas.keys
      .where((k) => k != 'solver')
      .every((k) => picked[k]!.length >= quotas[k]!);

  // Spread selection across games (avoid clustering in one Pluribus session) by
  // striding through the sorted file list.
  final stride = (files.length / (count * 12)).clamp(1, 997).floor();
  var scanned = 0;
  for (var i = 0; i < files.length && !full(); i += stride) {
    scanned++;
    final cand = _classify(files[i]);
    if (cand == null) continue;
    // Route a preflop all-in to the solver bucket, but if that's full fall back
    // to its board-texture bucket rather than dropping the hand.
    var bucket = cand.preflopAllIn ? 'solver' : cand.texture.name;
    if (picked[bucket]!.length >= quotas[bucket]!) bucket = cand.texture.name;
    final list = picked[bucket]!;
    if (list.length >= quotas[bucket]!) continue;
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

  // Walk the action log once: build the board, track who folded, and track who
  // made a VOLUNTARY postflop action (cc = check/call, cbr = bet/raise).
  final board = <String>[];
  final folds = <int>{};
  final postflopActors = <int>{};
  var boardDeals = 0;
  var seenBoard = false;
  for (final t in phh.actionTokens) {
    final tt = t.trim();
    if (tt.startsWith('d db ')) {
      board.addAll(_splitBoard(tt.substring(5).trim()));
      boardDeals++;
      seenBoard = true;
      continue;
    }
    final f = RegExp(r'^p(\d+) f$').firstMatch(tt);
    if (f != null) {
      folds.add(int.parse(f.group(1)!));
      continue;
    }
    if (seenBoard) {
      final a = RegExp(r'^p(\d+) (cc|cbr)(?: |$)').firstMatch(tt);
      if (a != null) postflopActors.add(int.parse(a.group(1)!));
    }
  }
  if (board.length < 3) return null; // need a flop+ to have board texture
  // >3 board deals (run-it-twice) can't be represented; the baker skips these.
  if (boardDeals > 3) return null;

  final survivors = phh.knownHolePlayers.difference(folds);
  if (survivors.isEmpty) return null;
  final preflopAllIn = _hasPreflopAllIn(phh);

  // Hero = lowest-index known-cards player who never folded. For a CARD-LOGIC
  // spot the hero must also have a real postflop decision to grade (without
  // this, a preflop all-in who never acts again could be the "hero" of a spot
  // with no streets to score). A SOLVER spot is the opposite: the graded
  // decision IS the preflop all-in, so the hero needn't act postflop.
  final int hero;
  if (preflopAllIn) {
    hero = (survivors.toList()..sort()).first;
  } else {
    final heroes = survivors.intersection(postflopActors).toList()..sort();
    if (heroes.isEmpty) return null;
    hero = heroes.first;
  }

  final texture = analyzeBoard(board).category;
  return Candidate(path, _gameOf(path), _handOf(path), hero, texture, board,
      preflopAllIn);
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
