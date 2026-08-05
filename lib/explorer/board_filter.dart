// GTO Explorer — board-picker filter model: parse each scenario's solved flops
// once into [BoardInfo] (texture cell + top rank + a search key), then filter
// with chip sets (suitedness / pairing / high card A..2) + a text query.
//
// The texture axes reuse lib/equity/texture_cell.dart UNCHANGED — the same
// classifier the frequency library keys on, so the picker's "Monotone" chip and
// the coaching FACT's texture cell can never disagree. The high-card chips are
// the EXACT top rank (A..2, from the parsed cards), NOT the classifier's
// 4-bucket HighCard enum — 13 chips filter a 1,755-board scenario far tighter
// than 4 buckets would.
//
// Pure Dart (no Flutter import) — unit-tested in test/explorer/.

import '../equity/card.dart';
import '../equity/texture_cell.dart';

/// Parse a 'Ks 9h 4c' flop label into card indices, or null when any token is
/// malformed (a bad hosted index row must not crash the picker).
List<int>? parseFlop(String flop) {
  final parts = flop.trim().split(RegExp(r'\s+'));
  if (parts.length < 3) return null;
  final cards = <int>[];
  for (final p in parts) {
    final c = parseCard(p);
    if (c < 0) return null;
    cards.add(c);
  }
  return cards;
}

/// One board's precomputed filter facets.
class BoardInfo {
  final String flop; // the display/index label, 'Ks 9h 4c'
  final TextureCell? texture; // null when the label failed to parse
  final String? highRankChar; // exact top rank, 'A'..'2'
  final String searchKey; // lowercased, whitespace stripped: 'ks9h4c'
  const BoardInfo({
    required this.flop,
    required this.texture,
    required this.highRankChar,
    required this.searchKey,
  });
}

/// Normalize a search query the same way [BoardInfo.searchKey] is built, so
/// 'Ks 9' and 'ks9' match identically.
String _normalizeQuery(String q) => q.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// Build the [BoardInfo] list ONCE per picker open — filtering then never
/// re-parses (the recompute on each keystroke is set-membership + contains).
List<BoardInfo> buildBoardInfos(List<String> flops) {
  BoardInfo info(String flop) {
    final cards = parseFlop(flop);
    return BoardInfo(
      flop: flop,
      texture: cards == null ? null : textureCell(cards),
      highRankChar: cards == null
          ? null
          : kRankChars[cards.map(cardRank).reduce((a, b) => a > b ? a : b)],
      searchKey: _normalizeQuery(flop),
    );
  }

  return [for (final f in flops) info(f)];
}

/// The picker's filter state. Empty sets / empty query = no restriction on
/// that axis; axes AND together, values within a set OR (the SessionFilter
/// multi-select convention).
class BoardFilter {
  final Set<SuitPattern> suits;
  final Set<Pairing> pairing;
  final Set<String> highRanks; // exact rank chars, 'A'..'2'
  final String query;
  const BoardFilter({
    this.suits = const {},
    this.pairing = const {},
    this.highRanks = const {},
    this.query = '',
  });

  bool get isEmpty =>
      suits.isEmpty && pairing.isEmpty && highRanks.isEmpty && query.trim().isEmpty;

  bool matches(BoardInfo info) {
    final t = info.texture;
    if (suits.isNotEmpty && (t == null || !suits.contains(t.suit))) return false;
    if (pairing.isNotEmpty && (t == null || !pairing.contains(t.pairing))) {
      return false;
    }
    if (highRanks.isNotEmpty &&
        (info.highRankChar == null || !highRanks.contains(info.highRankChar))) {
      return false;
    }
    final q = _normalizeQuery(query);
    if (q.isNotEmpty && !info.searchKey.contains(q)) return false;
    return true;
  }
}

List<BoardInfo> applyBoardFilter(List<BoardInfo> infos, BoardFilter filter) =>
    filter.isEmpty ? infos : [for (final i in infos) if (filter.matches(i)) i];

// ── Chip labels ──────────────────────────────────────────────────────────────

String suitPatternLabel(SuitPattern s) => switch (s) {
      SuitPattern.rainbow => 'Rainbow',
      SuitPattern.twotone => 'Two-tone',
      SuitPattern.monotone => 'Monotone',
    };

String pairingLabel(Pairing p) => switch (p) {
      Pairing.unpaired => 'Unpaired',
      Pairing.paired => 'Paired',
    };
