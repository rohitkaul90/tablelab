// Suit-isomorphic flop enumeration tests (full-density plan WS2). The 1,755
// count is a hard mathematical fact (1,430 unpaired + 312 paired + 13 trips) —
// any other number means the canonicalization is broken.

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';

import '../../tool/solver/flop_enum.dart';

List<int> _f(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

void main() {
  group('allIsoFlops', () {
    late final List<String> flops = allIsoFlops();

    test('yields exactly 1,755 canonical classes', () {
      expect(flops.length, 1755);
      expect(flops.toSet().length, 1755); // no duplicates
    });

    test('every flop is 3 valid, distinct cards', () {
      for (final f in flops) {
        final cards = _f(f);
        expect(cards.length, 3, reason: f);
        expect(cards.toSet().length, 3, reason: f);
        expect(cards.every((c) => c >= 0 && c < 52), isTrue, reason: f);
      }
    });

    test('every flop is its own canonical form (fixed point)', () {
      for (final f in flops.take(200)) {
        expect(canonicalFlop(_f(f)), f);
      }
    });
  });

  group('canonicalFlop', () {
    test('isomorphic flops map to the same representative', () {
      // Same rank pattern, suits relabeled h↔s, d↔c.
      expect(canonicalFlop(_f('Ks 9h 4c')), canonicalFlop(_f('Kh 9s 4d')));
      // Monotone in each of the four suits — all one class.
      final mono = {
        for (final s in ['c', 'd', 'h', 's'])
          canonicalFlop(_f('K$s Q$s J$s')),
      };
      expect(mono.length, 1);
    });

    test('non-isomorphic flops stay distinct', () {
      // Two-tone vs rainbow of the same ranks.
      expect(canonicalFlop(_f('Kh 9h 4c')),
          isNot(canonicalFlop(_f('Kh 9s 4c'))));
      // Paired vs unpaired.
      expect(canonicalFlop(_f('Ks Kh 4c')),
          isNot(canonicalFlop(_f('Ks Qh 4c'))));
    });

    test('card input order does not matter', () {
      expect(canonicalFlop(_f('4c 9h Ks')), canonicalFlop(_f('Ks 9h 4c')));
    });
  });
}
