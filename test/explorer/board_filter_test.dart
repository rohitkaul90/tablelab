import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/texture_cell.dart';
import 'package:tablelab/explorer/board_filter.dart';

/// The board-picker filter model: texture facets from the shared classifier,
/// exact-rank high-card chips (NOT the 4-bucket HighCard enum), and the
/// whitespace/case-insensitive text search.
void main() {
  final infos = buildBoardInfos([
    'Ks 9h 4c', // twotone? no — 3 suits → rainbow, unpaired, high K
    '7s 5s 2s', // monotone, unpaired, high 7
    'Ah Kh 4c', // twotone, unpaired, high A
    'Qd Qc 2h', // rainbow, paired, high Q
  ]);

  test('parseFlop parses labels and rejects malformed ones', () {
    expect(parseFlop('Ks 9h 4c'), hasLength(3));
    expect(parseFlop('Ks 9h'), isNull); // too short
    expect(parseFlop('Ks 9h 4c 2d'), isNull); // 4 cards — not a flop
    expect(parseFlop('Ks 9h Xx'), isNull); // bad card
  });

  test('buildBoardInfos derives texture, exact top rank, and search key', () {
    expect(infos[0].texture!.suit, SuitPattern.rainbow);
    expect(infos[0].texture!.pairing, Pairing.unpaired);
    expect(infos[0].highRankChar, 'K');
    expect(infos[0].searchKey, 'ks9h4c');
    expect(infos[1].texture!.suit, SuitPattern.monotone);
    expect(infos[1].highRankChar, '7');
    expect(infos[3].texture!.pairing, Pairing.paired);
    expect(infos[3].highRankChar, 'Q');
  });

  test('an unparseable board carries null facets but still lists', () {
    final bad = buildBoardInfos(['garbage']).single;
    expect(bad.texture, isNull);
    expect(bad.highRankChar, isNull);
    // …and any texture/rank chip then filters it out.
    expect(
        applyBoardFilter(
            [bad], const BoardFilter(suits: {SuitPattern.rainbow})),
        isEmpty);
  });

  test('empty filter matches everything (no-op fast path)', () {
    expect(applyBoardFilter(infos, const BoardFilter()), hasLength(4));
  });

  test('chip axes AND together; values within a set OR', () {
    expect(
      applyBoardFilter(infos, const BoardFilter(suits: {SuitPattern.rainbow}))
          .map((i) => i.flop),
      ['Ks 9h 4c', 'Qd Qc 2h'],
    );
    expect(
      applyBoardFilter(
        infos,
        const BoardFilter(
            suits: {SuitPattern.rainbow, SuitPattern.monotone}),
      ).map((i) => i.flop),
      ['Ks 9h 4c', '7s 5s 2s', 'Qd Qc 2h'],
    );
    expect(
      applyBoardFilter(
        infos,
        const BoardFilter(
            suits: {SuitPattern.rainbow}, pairing: {Pairing.paired}),
      ).map((i) => i.flop),
      ['Qd Qc 2h'],
    );
  });

  test('high-card chips filter on the EXACT top rank', () {
    expect(
      applyBoardFilter(infos, const BoardFilter(highRanks: {'K'}))
          .map((i) => i.flop),
      ['Ks 9h 4c'], // NOT 'Ah Kh 4c' — its top rank is A
    );
    expect(
      applyBoardFilter(infos, const BoardFilter(highRanks: {'A', '7'}))
          .map((i) => i.flop),
      ['7s 5s 2s', 'Ah Kh 4c'],
    );
  });

  test('search is case-insensitive and whitespace-insensitive', () {
    for (final q in ['ks9', 'Ks 9', 'KS 9H', ' ks  9h ']) {
      expect(
        applyBoardFilter(infos, BoardFilter(query: q)).map((i) => i.flop),
        ['Ks 9h 4c'],
        reason: 'query "$q"',
      );
    }
    expect(applyBoardFilter(infos, const BoardFilter(query: 'zz')), isEmpty);
  });

  test('search ANDs with chips', () {
    expect(
      applyBoardFilter(
        infos,
        const BoardFilter(query: '4c', suits: {SuitPattern.twotone}),
      ).map((i) => i.flop),
      ['Ah Kh 4c'],
    );
  });

  test('chip labels', () {
    expect(suitPatternLabel(SuitPattern.rainbow), 'Rainbow');
    expect(suitPatternLabel(SuitPattern.twotone), 'Two-tone');
    expect(suitPatternLabel(SuitPattern.monotone), 'Monotone');
    expect(pairingLabel(Pairing.paired), 'Paired');
    expect(pairingLabel(Pairing.unpaired), 'Unpaired');
  });
}
