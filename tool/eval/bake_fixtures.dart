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

import 'board_texture.dart';
import 'forced_decision.dart';
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

    // Parse + model in one try: the stricter parser (quote-aware arrays, card
    // validation, >3-board guard) can throw at PARSE time too (FormatException,
    // StateError, or a RangeError/CastError on a malformed file), so one bad
    // corpus file must skip the spot, not abort the whole batch.
    final PokerHand hand;
    try {
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
      hand = phhToPokerHand(
        phh,
        heroPlayer: hero,
        id: id,
        playedAt: _bakedAt,
        isTournament: spot['isTournament'] as bool? ?? false,
        tournamentStage: spot['tournamentStage'] as String?,
        notes: spot['notes'] as String?,
      );
    } on FormatException catch (e) {
      stderr.writeln('SKIP $id: malformed hand ($e)');
      skipped++;
      continue;
    } on StateError catch (e) {
      stderr.writeln('SKIP $id: unsupported hand ($e)');
      skipped++;
      continue;
    } catch (e) {
      stderr.writeln('SKIP $id: parse error ($e)');
      skipped++;
      continue;
    }

    // The equity sim, labelling (incl. computeForcedDecision), and write are
    // guarded too — like the parse step, a throw on one pathological hand must
    // skip the spot, not abort the whole batch.
    try {
      // Fixed seed → reproducible equity, so re-baking an unchanged spot
      // produces a byte-identical fixture (checked-in fixtures must be diffable).
      final equity = await computeHandEquityCheck(hand, reads: reads, seed: 1234);
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
    } catch (e) {
      stderr.writeln('SKIP $id: labelling/equity error ($e)');
      skipped++;
      continue;
    }
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

  // Forced-decision ground truth for verdict-agreement (null when the hand has
  // no pot-odds-decisive spot — most do not).
  final forced = computeForcedDecision(hand, equity);

  return {
    'heroHoleCards': heroCards,
    'finalBoard': hand.allCommunityCards,
    'perStreet': perStreet,
    'forcedDecision': forced?.toJson(),
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

/// Board-level possibility flags + the exact straight windows the board allows
/// (from the shared `analyzeBoard` — see board_texture.dart). Independent of the
/// prompt's TS computeBoardSummary; that cross-check is the point.
Map<String, dynamic> _boardTexture(List<String> board) =>
    analyzeBoard(board).toLabel();
