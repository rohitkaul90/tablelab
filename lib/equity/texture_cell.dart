// GTO frequency library (DCE Q1) — board TEXTURE CELL classifier.
//
// The frequency library keys on a DISCRETE, categorical board texture (not a
// learned clustering and not the exact flop) so the offline tabulator and the
// live FACT path map a board to a cell IDENTICALLY — the same cross-impl
// discipline EQR / board-volatility use. See launch/GTO_FREQUENCY_LIBRARY.md §1.
//
// A texture cell = 4 categorical axes, each computed from primitives the engine
// already reasons about:
//   suit pattern   rainbow | twotone | monotone   (max same-suit count: ≤1 / 2 / ≥3)
//   pairing        unpaired | paired              (any rank appears ≥2 on board)
//   high-card      ace | broadway | middling | low (the top board rank)
//   connectedness  connected | disconnected       (board supplies a ≥3-of-5 straight window)
//
// Defined for ANY board length ≥3 (flop/turn/river) so turn/river nodes can be
// re-bucketed by their RESULTING texture during tabulation. Pure Dart, isolate-
// safe (no Flutter import) — runs in the equity compute() isolate and under
// `dart run` for the tool. Unit-tested in test/equity/texture_cell_test.dart.

import 'card.dart';

/// Max same-suit count on the board → flush potential.
enum SuitPattern { rainbow, twotone, monotone }

/// Whether the board itself is paired (a rank repeats).
enum Pairing { unpaired, paired }

/// Coarse bucket of the highest board rank.
enum HighCard { ace, broadway, middling, low }

/// Whether the board offers straight connectivity.
enum Connectedness { connected, disconnected }

/// A discrete board-texture cell — the library's board key.
class TextureCell {
  final SuitPattern suit;
  final Pairing pairing;
  final HighCard highCard;
  final Connectedness connectedness;

  const TextureCell(this.suit, this.pairing, this.highCard, this.connectedness);

  /// Canonical key string, e.g. "twotone|unpaired|broadway|connected".
  /// Order: suit | pairing | highcard | connectedness (stable — used as a map key).
  String get key => '${suit.name}|${pairing.name}|${highCard.name}|'
      '${connectedness.name}';

  @override
  String toString() => key;

  @override
  bool operator ==(Object other) => other is TextureCell && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Classify [board] (parsed card ints, length ≥3) into its [TextureCell].
/// Returns null for a board too short to have a texture (< 3 cards).
TextureCell? textureCell(List<int> board) {
  if (board.length < 3) return null;

  // ── suit pattern: the largest same-suit count.
  final suitCounts = <int, int>{};
  for (final c in board) {
    final s = cardSuit(c);
    suitCounts[s] = (suitCounts[s] ?? 0) + 1;
  }
  final maxSuit = suitCounts.values.fold(0, (m, v) => v > m ? v : m);
  final suit = maxSuit >= 3
      ? SuitPattern.monotone
      : (maxSuit == 2 ? SuitPattern.twotone : SuitPattern.rainbow);

  // ── pairing: any rank appearing ≥2 (trips/quads fold into paired).
  final rankCounts = <int, int>{};
  for (final c in board) {
    final r = cardRank(c);
    rankCounts[r] = (rankCounts[r] ?? 0) + 1;
  }
  final paired = rankCounts.values.any((v) => v >= 2);
  final pairing = paired ? Pairing.paired : Pairing.unpaired;

  // ── high card: bucket the top board rank (rank index 0=2 .. 12=A).
  final topRank = rankCounts.keys.fold(0, (m, r) => r > m ? r : m);
  final HighCard highCard;
  if (topRank == 12) {
    highCard = HighCard.ace; // A
  } else if (topRank >= 9) {
    highCard = HighCard.broadway; // K/Q/J
  } else if (topRank >= 6) {
    highCard = HighCard.middling; // T/9/8
  } else {
    highCard = HighCard.low; // ≤7
  }

  // ── connectedness: does the board supply ≥3 of any 5-rank straight window?
  final connectedness = _hasStraightWindow(board)
      ? Connectedness.connected
      : Connectedness.disconnected;

  return TextureCell(suit, pairing, highCard, connectedness);
}

/// True when the board's rank VALUES supply ≥3 cards of some 5-rank straight
/// window (i.e. a straight is reachable with two hole cards). Mirrors the
/// board-volatility `_supplyWindows` logic (ace plays high and low). Distinct
/// values only — a paired board still counts its distinct ranks toward windows.
bool _hasStraightWindow(List<int> board) {
  final present = <int>{};
  for (final c in board) {
    final v = cardRank(c) + 2; // rank 0..12 → value 2..14
    present.add(v);
    if (v == 14) present.add(1); // ace also plays low
  }
  for (var low = 1; low <= 10; low++) {
    var onBoard = 0;
    for (var v = low; v < low + 5; v++) {
      if (present.contains(v)) onBoard++;
    }
    if (onBoard >= 3) return true;
  }
  return false;
}
