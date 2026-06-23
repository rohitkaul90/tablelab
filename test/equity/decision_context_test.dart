import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/decision_context.dart';

List<int> _cards(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

void main() {
  group('classifyHandClass', () {
    test('pre-flop (board < 3) is unclassifiable', () {
      expect(classifyHandClass(_cards('Ah Kd'), const []), isNull);
    });

    test('two pair+ is strongMade', () {
      // Trips (AhAd + As)
      expect(classifyHandClass(_cards('Ah Ad'), _cards('As Kd 7c')),
          HandClass.strongMade);
      // Two pair (aces + kings)
      expect(classifyHandClass(_cards('Ah Kh'), _cards('As Kd 7c')),
          HandClass.strongMade);
      // Made flush
      expect(classifyHandClass(_cards('Ah 5h'), _cards('Kh 2h 9h')),
          HandClass.strongMade);
    });

    test('one pair using hole cards is marginalMade', () {
      expect(classifyHandClass(_cards('Ah Qd'), _cards('As 7c 2d')),
          HandClass.marginalMade);
    });

    test('nut flush draw is strongDraw', () {
      // Ah + three more hearts on board → 4 hearts, hero holds Ah → nut FD
      expect(classifyHandClass(_cards('Ah 5h'), _cards('Kh 2h 9c')),
          HandClass.strongDraw);
    });

    test('open-ended straight draw is strongDraw', () {
      // 9-8 on 7-6-2 → 9-8-7-6, open-ended (completes with T or 5)
      expect(classifyHandClass(_cards('9h 8d'), _cards('7c 6s 2h')),
          HandClass.strongDraw);
    });

    test('gutshot is weakDraw', () {
      // 9-6 on 7-5-2 → 9-7-6-5 needs an 8 only → gutshot
      expect(classifyHandClass(_cards('9h 6d'), _cards('7c 5s 2h')),
          HandClass.weakDraw);
    });

    test('high card with no draw is air', () {
      expect(classifyHandClass(_cards('Ah 3d'), _cards('Kc 8s 2h')),
          HandClass.air);
    });

    test('playing the board (no hole contribution) is not a made hand', () {
      // Board trips kings on a 5-card board; hero 3-2 only plays the board.
      expect(classifyHandClass(_cards('3h 2d'), _cards('Ks Kd Kc 9s 4h')),
          HandClass.air);
    });
  });

  group('eqrMultiplier — hard anchors', () {
    test('NFD in position ≈ 1.00', () {
      expect(eqrMultiplier(HandClass.strongDraw, HeroPosition.ip), 1.00);
    });
    test('weak FD in position ≈ 0.87 (0.88 here)', () {
      expect(eqrMultiplier(HandClass.weakDraw, HeroPosition.ip), 0.88);
    });
    test('one pair out of position (BB-defend) ≈ 0.79', () {
      expect(eqrMultiplier(HandClass.marginalMade, HeroPosition.oop), 0.79);
    });
    test('strong made over-realizes (> 1) in position', () {
      expect(eqrMultiplier(HandClass.strongMade, HeroPosition.ip),
          greaterThan(1.0));
    });
    test('IP realizes ≥ OOP for every class', () {
      for (final hc in HandClass.values) {
        expect(eqrMultiplier(hc, HeroPosition.ip),
            greaterThanOrEqualTo(eqrMultiplier(hc, HeroPosition.oop)),
            reason: '$hc');
      }
    });
  });

  group('realizedEquity', () {
    test('clamps to [0, 1] when a strong made hand over-realizes', () {
      // 0.9 × 1.30 = 1.17 → clamped to 1.0
      expect(
          realizedEquity(0.9,
              handClass: HandClass.strongMade, position: HeroPosition.ip),
          1.0);
    });

    test('air out of position realizes almost nothing', () {
      expect(
          realizedEquity(0.5,
              handClass: HandClass.air, position: HeroPosition.oop),
          closeTo(0.05, 1e-9));
    });

    test('monotonic by hand strength at fixed raw equity + position', () {
      double r(HandClass hc) =>
          realizedEquity(0.45, handClass: hc, position: HeroPosition.oop);
      expect(r(HandClass.strongMade), greaterThan(r(HandClass.marginalMade)));
      expect(r(HandClass.marginalMade), greaterThan(r(HandClass.weakDraw)));
      expect(r(HandClass.weakDraw), greaterThan(r(HandClass.air)));
    });
  });

  group('classifyHandClass — review-fix regressions', () {
    test('overcards on a PAIRED FLOP are air, not marginalMade (#1)', () {
      // The pair is the board's (KK); AQ does not pair in → hero plays the board.
      expect(classifyHandClass(_cards('Ah Qd'), _cards('Ks Kc 7d')),
          HandClass.air);
    });

    test('a board-only straight draw hero does not contribute to is air (#2)', () {
      // 5-6-7-8 open-ender belongs to the board; hero 2-3 only shares it.
      expect(classifyHandClass(_cards('2c 3d'), _cards('5h 6s 7c 8d')),
          HandClass.air);
    });

    test('a busted draw on the RIVER is air, not a draw (#3)', () {
      // 4 hearts but it is the river (5-card board) — no card left to come.
      expect(classifyHandClass(_cards('Ah 5h'), _cards('Kh 2h 9c Td 3s')),
          HandClass.air);
    });

    test('top pair + nut flush draw is a combo → strongMade, not marginalMade (#4)', () {
      // Kh pairs the Ks; Ah+Kh + two board hearts = nut flush draw.
      expect(classifyHandClass(_cards('Ah Kh'), _cards('Ks 7h 2h')),
          HandClass.strongMade);
    });

    test('a pocket pair below the board is still hero\'s own made hand', () {
      expect(classifyHandClass(_cards('9h 9d'), _cards('Ks 7c 2d')),
          HandClass.marginalMade);
    });
  });

  group('classifyFromStrings', () {
    test('parses card strings and matches classifyHandClass', () {
      expect(classifyFromStrings(['Ah', 'Qd'], ['As', '7c', '2d']),
          HandClass.marginalMade);
    });
    test('null on too few hole cards', () {
      expect(classifyFromStrings(['Ah'], ['As', '7c', '2d']), isNull);
    });
  });
}
