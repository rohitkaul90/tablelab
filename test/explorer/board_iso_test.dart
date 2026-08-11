// Suit-normalizer tests: the canonicalization MOVED from tool/solver/
// flop_enum.dart stays byte-identical to the committed artifacts, loose user
// input canonicalizes to the stored spot label, and turn/river suit
// equivalence routes pruned twins to their stored representatives.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';
import 'package:tablelab/explorer/board_iso.dart';

import '../../tool/solver/flop_enum.dart' as tool;

List<int> _f(String s) => s.split(' ').map(parseCard).toList();

void main() {
  group('canonicalFlop move (one implementation, frozen output)', () {
    test('tool/solver/flop_enum.dart re-exports THIS implementation', () {
      // identical() on the tear-offs proves the tool module shares the lib
      // functions rather than carrying a fork that could drift.
      expect(identical(tool.canonicalFlop, canonicalFlop), isTrue);
      expect(identical(tool.allIsoFlops, allIsoFlops), isTrue);
    });

    test('all 22,100 raw flops collapse to EXACTLY the committed 1,755 set',
        () {
      final seen = <String>{};
      for (var a = 0; a < 52; a++) {
        for (var b = a + 1; b < 52; b++) {
          for (var c = b + 1; c < 52; c++) {
            seen.add(canonicalFlop([a, b, c]));
          }
        }
      }
      expect(seen.length, 1755);
      // Byte-identity with the PRE-MOVE artifact: the committed bulk-campaign
      // slice files partition the canonical set (locked in
      // test/solver/flop_enum_test.dart), so their union must equal the moved
      // implementation's output exactly — any drift breaks every solved pack.
      final committed = <String>{};
      for (var k = 0; k < 5; k++) {
        committed.addAll(File('tool/solver/flops/slice351_off$k.txt')
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#')));
      }
      expect(seen, committed);
    });
  });

  group('canonicalizeFlopString', () {
    test('any suit spelling of a board maps to its canonical spot label', () {
      expect(canonicalizeFlopString('As7s6s'), canonicalFlop(_f('As 7s 6s')));
      // Monotone canonicalizes to clubs; card order is irrelevant.
      for (final q in ['As7s6s', 'as 7s 6s', 'AS,7S,6S', 'A♠7♠6♠', '6s As 7s']) {
        expect(canonicalizeFlopString(q), 'Ac 7c 6c', reason: 'input "$q"');
      }
      // Rainbow: minimal suit assignment in rank-desc order.
      expect(canonicalizeFlopString('Ks 9h 4c'), 'Kc 9d 4h');
    });

    test('accepts 10 for T', () {
      expect(
          canonicalizeFlopString('10s 9h 4c'), canonicalFlop(_f('Ts 9h 4c')));
    });

    test('rejects non-boards', () {
      expect(canonicalizeFlopString(''), isNull);
      expect(canonicalizeFlopString('As 7s'), isNull); // 2 cards
      expect(canonicalizeFlopString('As 7s 6s 5s'), isNull); // 4 cards
      expect(canonicalizeFlopString('As As 6s'), isNull); // duplicate
      expect(canonicalizeFlopString('garbage'), isNull);
      expect(canonicalizeFlopString('Ax 7s 6s'), isNull); // bad suit
    });
  });

  group('equivalentCards', () {
    test('monotone flop: the three off-suits are one class', () {
      const flop = ['Ac', '7c', '6c'];
      expect(
          equivalentCards('2s', fixedCards: flop).toSet(), {'2d', '2h', '2s'});
      // The flush suit is its own class.
      expect(equivalentCards('2c', fixedCards: flop), ['2c']);
      // Same rank as a board card, off-suit: still the full off-suit class.
      expect(
          equivalentCards('7d', fixedCards: flop).toSet(), {'7d', '7h', '7s'});
    });

    test('rainbow flop: every suit is its own class', () {
      const flop = ['Ks', '9h', '4c'];
      for (final card in ['2c', '2d', '2h', '2s']) {
        expect(equivalentCards(card, fixedCards: flop), [card]);
      }
    });

    test('two-tone flop: the two absent suits are interchangeable', () {
      const flop = ['Kh', '9h', '4c'];
      expect(equivalentCards('As', fixedCards: flop).toSet(), {'Ad', 'As'});
      expect(equivalentCards('Ah', fixedCards: flop), ['Ah']);
      expect(equivalentCards('Ac', fixedCards: flop), ['Ac']);
    });

    test('a board card has no equivalents (collision)', () {
      expect(equivalentCards('Kh', fixedCards: ['Kh', '9h', '4c']), isEmpty);
    });

    test('river-level: the turn card splits its suit out of the class', () {
      // Monotone club flop + 2d turn: d now differs from h/s.
      const board = ['Ac', '7c', '6c', '2d'];
      expect(equivalentCards('Ks', fixedCards: board).toSet(), {'Kh', 'Ks'});
      expect(equivalentCards('Kd', fixedCards: board), ['Kd']);
    });
  });

  group('representativeFor', () {
    const flop = ['Ac', '7c', '6c'];

    test('prefers the desired card when stored', () {
      expect(
          representativeFor('2d', fixedCards: flop, available: {'2d', '2h'}),
          '2d');
    });

    test('routes an absent card to its stored twin (deterministic order)', () {
      expect(
          representativeFor('2s', fixedCards: flop, available: {'2d', '2h'}),
          '2d'); // first equivalent in c-d-h-s order
      expect(representativeFor('2s', fixedCards: flop, available: {'2h'}),
          '2h');
    });

    test('null when no equivalent is stored or the card collides', () {
      // 2c is the flush suit — a DIFFERENT class, never a stand-in for 2s.
      expect(representativeFor('2s', fixedCards: flop, available: {'2c'}),
          isNull);
      // Collides with the board.
      expect(representativeFor('Ac', fixedCards: flop, available: {'Ad'}),
          isNull);
    });
  });
}
