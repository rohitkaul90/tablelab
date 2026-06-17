// Stage 1 of the eval harness: bake checked-in fixtures from PHH hands.
//
// For each spot in the manifest (tool/eval/spots.json) this:
//   1. parses the PHH file -> PokerHand (phh_parser.dart),
//   2. computes the on-device equity cross-check exactly as the app does
//      (computeHandEquityCheck -> equityCheckFacts), so the fixture carries the
//      SAME equityFacts that ride into the production analyze-hand prompt, and
//   3. computes INDEPENDENT ground-truth labels from lib/equity/evaluator.dart
//      (hero's made-hand category, per-street hero equity, and board-level
//      possibility flags + the exact straight windows the board allows).
//
// The labels come from the Dart evaluator; the prompt's card-logic FACTs come
// from the TypeScript computeBoardSummary/computeDrawSummary in the Edge
// Function. Because they are SEPARATE implementations, the Stage 2 scorer
// comparing model output to these labels also catches FACT-generator bugs, not
// just model hallucinations (the whole point — see launch/EVAL_HARNESS.md).
//
// No model calls here: deterministic, free, reproducible. Run rarely (when the
// benchmark set changes), commit the fixtures.
//
//   dart run tool/eval/bake_fixtures.dart [spots.json] [outDir]

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/evaluator.dart';
import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';
import 'package:tablelab/models/player_read.dart';

import 'phh_parser.dart';

// Reproducible timestamp for every fixture (no DateTime.now()).
final _bakedAt = DateTime.utc(2026, 1, 1);

Future<void> main(List<String> args) async {
  final manifestPath = args.isNotEmpty ? args[0] : 'tool/eval/spots.json';
  final outDir = args.length > 1 ? args[1] : 'tool/eval/fixtures';

  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('manifest not found: $manifestPath');
    exit(2);
  }
  final spots = (jsonDecode(manifestFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  Directory(outDir).createSync(recursive: true);

  var baked = 0, skipped = 0;
  for (final spot in spots) {
    final id = spot['id'] as String;
    final file = spot['file'] as String;
    final hero = spot['hero'] as int;
    final bucket = spot['bucket'] as String? ?? 'card-logic';
    final reads = _parseReads(spot['reads']);

    final phhFile = File(file);
    if (!phhFile.existsSync()) {
      stderr.writeln('SKIP $id: phh file missing ($file)');
      skipped++;
      continue;
    }

    final phh = parsePhhText(phhFile.readAsStringSync());
    if (!phh.knownHolePlayers.contains(hero)) {
      stderr.writeln('SKIP $id: hero p$hero has no known hole cards');
      skipped++;
      continue;
    }
    final boardDeals =
        phh.actionTokens.where((t) => t.trim().startsWith('d db ')).length;
    if (boardDeals > 3) {
      stderr.writeln('SKIP $id: $boardDeals board deals '
          '(run-it-twice / multi-board not supported)');
      skipped++;
      continue;
    }

    final hand = phhToPokerHand(
      phh,
      heroPlayer: hero,
      id: id,
      playedAt: _bakedAt,
      isTournament: spot['isTournament'] as bool? ?? false,
      tournamentStage: spot['tournamentStage'] as String?,
      notes: spot['notes'] as String?,
    );

    final equity = await computeHandEquityCheck(hand, reads: reads);
    if (equity == null) {
      stderr.writeln('SKIP $id: equity check unmodelable (no opponents/cards)');
      skipped++;
      continue;
    }
    final facts = equityCheckFacts(equity);

    final labels = _buildLabels(hand, equity);

    // A spot with no postflop street has no board-level card-logic to score —
    // every claim would be skipped and the spot would report 100% clean
    // regardless of model errors. Don't bake it; it would inflate accuracy.
    if ((labels['perStreet'] as List).isEmpty) {
      stderr.writeln('SKIP $id: no postflop street to score (board never reached the flop)');
      skipped++;
      continue;
    }

    final fixture = <String, dynamic>{
      'id': id,
      'source': spot['source'] ?? file,
      'heroPlayer': hero,
      'bucket': bucket,
      'reads': reads
          .map((r) => {'playerLabel': r.playerLabel, 'tags': r.tags})
          .toList(),
      'hand': hand.toJson(),
      'equityFacts': facts,
      'labels': labels,
    };

    File('$outDir/$id.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(fixture));
    baked++;
    stdout.writeln('baked $id  ($bucket, ${labels['perStreet'].length} street labels)');
  }

  stdout.writeln('\nDone: $baked baked, $skipped skipped -> $outDir');
}

List<PlayerRead> _parseReads(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((r) {
    final m = r as Map<String, dynamic>;
    return PlayerRead(
      id: 'eval',
      userId: 'eval',
      playerLabel: m['playerLabel'] as String,
      tags: (m['tags'] as List).cast<String>(),
      createdAt: _bakedAt,
      updatedAt: _bakedAt,
    );
  }).toList();
}

Map<String, dynamic> _buildLabels(PokerHand hand, HandEquityCheck equity) {
  final hero = hand.hero!;
  final heroCards = hero.holeCards!;
  final equityByStreet = {for (final s in equity.streets) s.street: s.heroEquity};

  final perStreet = <Map<String, dynamic>>[];
  final boardSoFar = <String>[];
  for (final s in hand.streets) {
    boardSoFar.addAll(s.communityCards);
    if (boardSoFar.length < 3) continue; // preflop: no board card-logic to label
    final board = List<String>.from(boardSoFar);
    perStreet.add({
      'street': s.street.name,
      'board': board,
      'heroCategory': _heroCategory(heroCards, board),
      'heroEquity': equityByStreet[s.street],
      ..._boardTexture(board),
    });
  }

  return {
    'heroHoleCards': heroCards,
    'finalBoard': hand.allCommunityCards,
    'perStreet': perStreet,
  };
}

/// Hero's best made-hand category (objective, from the 7-card evaluator).
/// Uses the evaluator's own [handCategoryName] so the encoding (bit offset +
/// category ordering) lives in exactly one place.
String _heroCategory(List<String> hole, List<String> board) {
  final cards = [...hole, ...board].map(parseCard).where((c) => c >= 0).toList();
  // evaluateBest asserts 5..7 cards. 2 hole + ≤5 board satisfies it; guard both
  // bounds so a malformed fixture is labelled, not an assertion crash.
  if (cards.length < 5 || cards.length > 7) return 'INCOMPLETE';
  return handCategoryName(evaluateBest(cards));
}

/// Board-level possibility flags + the exact straight windows the board allows.
/// Independent reimplementation of the constraints computeBoardSummary asserts
/// in the prompt — a mismatch between this and the prompt FACT is a real bug.
Map<String, dynamic> _boardTexture(List<String> board) {
  final ranks = board.map((c) => cardRank(parseCard(c))).toList(); // 0=2..12=A
  final suits = board.map((c) => cardSuit(parseCard(c))).toList(); // 0=c..3=s

  final rankCount = <int, int>{};
  for (final r in ranks) {
    rankCount[r] = (rankCount[r] ?? 0) + 1;
  }
  final maxRankCount = rankCount.values.fold(0, (a, b) => a > b ? a : b);

  final suitCount = <int, int>{};
  for (final s in suits) {
    suitCount[s] = (suitCount[s] ?? 0) + 1;
  }
  int flushSuit = -1;
  var maxSuit = 0;
  suitCount.forEach((s, n) {
    if (n > maxSuit) {
      maxSuit = n;
      flushSuit = s;
    }
  });

  // Straight windows: rank values 2..14 (A high). Add A-low (1) for the wheel.
  // Window low..low+4; board "supplies" a window if >=3 of its 5 ranks are on
  // board (a player completes it with <=2 hole cards).
  final present = <int>{};
  for (final r in ranks) {
    final v = r + 2; // 0->2 ... 12->14
    present.add(v);
    if (v == 14) present.add(1);
  }
  const valLabel = {
    1: 'A', 2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7',
    8: '8', 9: '9', 10: 'T', 11: 'J', 12: 'Q', 13: 'K', 14: 'A',
  };
  final windows = <String>[];
  for (var low = 1; low <= 10; low++) {
    final win = [for (var v = low; v < low + 5; v++) v];
    final onBoard = win.where(present.contains).length;
    if (onBoard >= 3) {
      windows.add(win.map((v) => valLabel[v]).join('-'));
    }
  }

  const suitNames = ['clubs', 'diamonds', 'hearts', 'spades'];
  return {
    'boatOrQuadsPossible': maxRankCount >= 2,
    'flushPossible': maxSuit >= 3,
    'flushSuit': maxSuit >= 3 ? suitNames[flushSuit] : null,
    'allowedStraightWindows': windows,
  };
}
