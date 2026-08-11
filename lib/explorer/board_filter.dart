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
import 'board_iso.dart';

/// Parse a 'Ks 9h 4c' flop label into card indices, or null when it isn't
/// EXACTLY three well-formed cards (a bad hosted index row must not crash the
/// picker, and a 4-card label is not a flop).
List<int>? parseFlop(String flop) {
  final parts = flop.trim().split(RegExp(r'\s+'));
  if (parts.length != 3) return null;
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

/// The canonical-board search key for [query] when it parses as a FULL 3-card
/// board under ANY suit spelling — the library stores one suit-isomorphic
/// representative, so "as7s6s" must find the stored Ac7c6c. Null when the
/// query isn't a complete board (partial queries keep substring semantics).
String? canonicalQueryKey(String query) {
  final canonical = canonicalizeFlopString(query);
  return canonical == null ? null : _normalizeQuery(canonical);
}

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
    if (q.isNotEmpty && !info.searchKey.contains(q)) {
      // A full-board query in a non-canonical suit spelling still matches its
      // stored representative (suits are interchangeable).
      final canon = canonicalQueryKey(query);
      if (canon == null || info.searchKey != canon) return false;
    }
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
