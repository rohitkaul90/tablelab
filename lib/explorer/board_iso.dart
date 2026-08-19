// GTO Explorer — suit-isomorphism utilities: the canonical flop map the solve
// grid stores boards under, plus the user-facing normalizers that make the
// convention invisible (any-suit board search, equivalent-runout routing).
//
// The hosted pack library stores ONE representative per suit-isomorphism
// class: 1,755 canonical flops (every monotone A76 lives at "Ac 7c 6c"), and
// within a pack tree the solver pruned redundant turn/river suits (after
// Ac7c6c there are no spade turns — spades are isomorphic to the same-rank
// hearts/diamonds which ARE stored). Users don't know the convention, so this
// module translates their spelling to the stored one.
//
// [canonicalFlop]/[allIsoFlops] MOVED here from tool/solver/flop_enum.dart
// (which re-exports them — the pack_codec pattern) so the app and the solve
// tooling share ONE implementation. The algorithm is FROZEN: the committed
// slice files and every solved pack key off its exact output (byte-identity
// is test-locked in test/explorer/board_iso_test.dart and
// test/solver/flop_enum_test.dart).
//
// Pure Dart (no Flutter import) — unit-tested in test/explorer/.

import '../equity/card.dart';

/// All 1,755 canonical flops as "As Kd 7h"-style strings (the grid's flop
/// format), deterministic order (sorted).
List<String> allIsoFlops() {
  final seen = <String>{};
  for (var a = 0; a < 52; a++) {
    for (var b = a + 1; b < 52; b++) {
      for (var c = b + 1; c < 52; c++) {
        seen.add(canonicalFlop([a, b, c]));
      }
    }
  }
  final out = seen.toList()..sort();
  return out;
}

/// The canonical representative of [flop]'s suit-isomorphism class, as a
/// "Rr Rr Rr" string. Deterministic: minimum serialization over all 24 suit
/// permutations (cards sorted rank-desc, suit-asc within rank). Brute force
/// over 24 permutations is instant and immune to the classic
/// within-rank-ordering pitfalls of first-appearance relabeling.
String canonicalFlop(List<int> flop) {
  String? best;
  for (final perm in _kSuitPerms) {
    final mapped = [
      for (final c in flop) cardIndex(cardRank(c), perm[cardSuit(c)])
    ]..sort((x, y) {
        final r = cardRank(y).compareTo(cardRank(x)); // rank desc
        return r != 0 ? r : cardSuit(x).compareTo(cardSuit(y)); // suit asc
      });
    final s = mapped.map(cardName).join(' ');
    if (best == null || s.compareTo(best) < 0) best = s;
  }
  return best!;
}

/// Parse loose user text into EXACTLY three distinct cards, or null. Accepts
/// any case, optional space/comma/dash/slash separators, suit symbols (♣♦♥♠,
/// with or without the U+FE0F emoji variation selector keyboards append), and
/// "10" for T — "as 7s 6s", "A♠7♠6♠", "As-7s-6s", "10h9h4c". The result is
/// sorted rank-desc, suit-asc (the canonical serialization order) for stable
/// display.
List<int>? parseFlopInput(String input) {
  final s = input
      .replaceAll('\uFE0F', '') // ♠️-style emoji presentation → bare symbol
      .replaceAll('♣', 'c')
      .replaceAll('♦', 'd')
      .replaceAll('♥', 'h')
      .replaceAll('♠', 's')
      .replaceAll(RegExp(r'[\s,/\-]+'), '')
      .replaceAll('10', 'T');
  if (s.length != 6) return null;
  final cards = <int>[];
  for (var i = 0; i < 6; i += 2) {
    final c = parseCard(s.substring(i, i + 2));
    if (c < 0) return null;
    cards.add(c);
  }
  if (cards.toSet().length != 3) return null;
  cards.sort((x, y) {
    final r = cardRank(y).compareTo(cardRank(x)); // rank desc
    return r != 0 ? r : cardSuit(x).compareTo(cardSuit(y)); // suit asc
  });
  return cards;
}

/// [canonicalFlop] over loosely-spelled user text: "as7s6s" → "Ac 7c 6c" (the
/// spot-label format the board picker's search keys off). Null when [input]
/// isn't a complete 3-card board.
String? canonicalizeFlopString(String input) {
  final cards = parseFlopInput(input);
  return cards == null ? null : canonicalFlop(cards);
}

/// Every card suit-equivalent to [card] over [fixedCards] — INCLUDING [card]
/// itself — in deterministic c-d-h-s order. Two cards are equivalent iff they
/// share a rank, their suits hold the SAME rank-multiset among the fixed board
/// cards (the exact condition under which the solver's pruning merged the
/// runouts), and neither collides with a fixed card. Returns const [] when
/// [card] is malformed or itself collides with the board.
List<String> equivalentCards(String card, {required List<String> fixedCards}) {
  final c = parseCard(card);
  if (c < 0) return const [];
  final fixed = <int>[];
  for (final f in fixedCards) {
    final fi = parseCard(f);
    if (fi >= 0) fixed.add(fi);
  }
  if (fixed.contains(c)) return const [];
  final classes = _suitClasses(fixed);
  final rank = cardRank(c);
  final cls = classes[cardSuit(c)];
  return [
    for (var s = 0; s < 4; s++)
      if (classes[s] == cls && !fixed.contains(cardIndex(rank, s)))
        cardName(cardIndex(rank, s)),
  ];
}

/// The stored representative for [desiredCard]: the card itself when in
/// [available], else its first available suit-equivalent (c-d-h-s order), else
/// null (a genuinely absent runout — not an isomorphism gap).
String? representativeFor(String desiredCard,
    {required List<String> fixedCards, required Set<String> available}) {
  final eq = equivalentCards(desiredCard, fixedCards: fixedCards);
  if (eq.isEmpty) return null; // malformed, or collides with the board
  if (available.contains(desiredCard)) return desiredCard;
  for (final c in eq) {
    if (available.contains(c)) return c;
  }
  return null;
}

/// Class id per suit (0..3): suits with identical rank-multisets over [fixed]
/// share an id — the transposition of two such suits maps the board to itself,
/// so their runout cards are interchangeable.
List<int> _suitClasses(List<int> fixed) {
  final keys = List.generate(4, (s) {
    final ranks = [
      for (final c in fixed)
        if (cardSuit(c) == s) cardRank(c)
    ]..sort();
    return ranks.join(',');
  });
  return [for (var s = 0; s < 4; s++) keys.indexOf(keys[s])];
}

/// All 24 permutations of the 4 suits, computed once.
final List<List<int>> _kSuitPerms = _perms([0, 1, 2, 3]);

List<List<int>> _perms(List<int> xs) {
  if (xs.length <= 1) return [xs];
  final out = <List<int>>[];
  for (var i = 0; i < xs.length; i++) {
    final rest = [...xs]..removeAt(i);
    for (final p in _perms(rest)) {
      out.add([xs[i], ...p]);
    }
  }
  return out;
}
