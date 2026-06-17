// Board-level texture classification, shared by the Stage-1 baker
// (bake_fixtures.dart, which turns it into ground-truth labels) and the curator
// (curate.dart, which buckets spots by it). One implementation so the set a
// hand is SELECTED into can never drift from the texture the fixture is LABELLED
// with.
//
// Note: this is intentionally independent of the *prompt*'s TypeScript
// computeBoardSummary — that duplication is the harness's cross-check (the Dart
// answer key vs the TS FACT generator). This file unifies only the Dart-to-Dart
// copies.

import 'package:tablelab/equity/card.dart';

/// Board-level constraints: what categories ANY hand could make on this board.
class BoardTexture {
  /// A full house or quads is possible (the board is paired or better).
  final bool boatOrQuadsPossible;

  /// A flush is possible (3+ of one suit on board).
  final bool flushPossible;

  /// The flushable suit name (clubs/diamonds/hearts/spades), or null.
  final String? flushSuit;

  /// The exact 5-rank straight windows the board can complete (board supplies
  /// >=3 of the 5 ranks), labelled high-low e.g. "6-7-8-9-T".
  final List<String> allowedStraightWindows;

  const BoardTexture({
    required this.boatOrQuadsPossible,
    required this.flushPossible,
    required this.flushSuit,
    required this.allowedStraightWindows,
  });

  /// As the JSON label map the baker writes into a fixture.
  Map<String, dynamic> toLabel() => {
        'boatOrQuadsPossible': boatOrQuadsPossible,
        'flushPossible': flushPossible,
        'flushSuit': flushSuit,
        'allowedStraightWindows': allowedStraightWindows,
      };

  /// Coarse single category for benchmark bucketing (priority paired > flush >
  /// straight > dry — a board can be several, the strongest temptation wins).
  TextureCategory get category {
    if (boatOrQuadsPossible) return TextureCategory.paired;
    if (flushPossible) return TextureCategory.flush;
    if (allowedStraightWindows.isNotEmpty) return TextureCategory.straight;
    return TextureCategory.dry;
  }
}

enum TextureCategory { paired, flush, straight, dry }

const _suitNames = ['clubs', 'diamonds', 'hearts', 'spades'];
const _valLabel = {
  1: 'A', 2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7',
  8: '8', 9: '9', 10: 'T', 11: 'J', 12: 'Q', 13: 'K', 14: 'A',
};

/// Classify a board. Invalid card tokens are skipped (defensive — a curator
/// scanning raw corpus shouldn't fabricate a phantom rank/suit from a bad card).
BoardTexture analyzeBoard(List<String> board) {
  final parsed = board.map(parseCard).where((c) => c >= 0).toList();
  final ranks = parsed.map(cardRank).toList(); // 0=2..12=A
  final suits = parsed.map(cardSuit).toList(); // 0=c..3=s

  final rankCount = <int, int>{};
  for (final r in ranks) {
    rankCount[r] = (rankCount[r] ?? 0) + 1;
  }
  final maxRankCount =
      rankCount.values.fold<int>(0, (a, b) => a > b ? a : b);

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

  // Straight windows: rank values 2..14 (A high) + A-low (1) for the wheel.
  final present = <int>{};
  for (final r in ranks) {
    final v = r + 2; // 0->2 ... 12->14
    present.add(v);
    if (v == 14) present.add(1);
  }
  final windows = <String>[];
  for (var low = 1; low <= 10; low++) {
    final win = [for (var v = low; v < low + 5; v++) v];
    final onBoard = win.where(present.contains).length;
    if (onBoard >= 3) {
      windows.add(win.map((v) => _valLabel[v]).join('-'));
    }
  }

  return BoardTexture(
    boatOrQuadsPossible: maxRankCount >= 2,
    flushPossible: maxSuit >= 3,
    flushSuit: maxSuit >= 3 ? _suitNames[flushSuit] : null,
    allowedStraightWindows: windows,
  );
}
