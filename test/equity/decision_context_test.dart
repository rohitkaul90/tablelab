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

  group('eqrMultiplier — solver-calibrated anchors', () {
    test('strong draw in position ≈ 1.05 (solver)', () {
      expect(eqrMultiplier(HandClass.strongDraw, HeroPosition.ip), 1.05);
    });
    test('weak draw in position ≈ 1.00 (solver)', () {
      expect(eqrMultiplier(HandClass.weakDraw, HeroPosition.ip), 1.00);
    });
    test('one pair out of position ≈ 0.75 (solver)', () {
      expect(eqrMultiplier(HandClass.marginalMade, HeroPosition.oop), 0.75);
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
      // 0.9 × 1.18 = 1.06 → clamped to 1.0
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

  group('requiredEquityToStackOff — sourced anchors', () {
    test('SPR 1 → ~33%', () {
      expect(requiredEquityToStackOff(1), closeTo(0.333, 0.005));
    });
    test('SPR 2 → ~40%', () {
      expect(requiredEquityToStackOff(2), closeTo(0.40, 0.005));
    });
    test('SPR 3 → ~43%', () {
      expect(requiredEquityToStackOff(3), closeTo(0.4286, 0.005));
    });
    test('asymptotes to (and never exceeds) 50%', () {
      expect(requiredEquityToStackOff(100), closeTo(0.4975, 0.005));
      expect(requiredEquityToStackOff(1e9), lessThanOrEqualTo(0.5));
    });
    test('monotonically increasing in SPR', () {
      double prev = -1;
      for (final spr in [0.5, 1.0, 2.0, 4.0, 8.0, 20.0]) {
        final r = requiredEquityToStackOff(spr);
        expect(r, greaterThan(prev), reason: 'SPR $spr');
        prev = r;
      }
    });
    test('non-positive SPR is 0', () {
      expect(requiredEquityToStackOff(0), 0.0);
      expect(requiredEquityToStackOff(-1), 0.0);
    });
  });

  group('sprBucket', () {
    test('boundaries map to the expected commitment bucket', () {
      expect(sprBucket(0.5), SprBucket.committed);
      expect(sprBucket(1.0), SprBucket.committed);
      expect(sprBucket(2.0), SprBucket.shallow);
      expect(sprBucket(3.0), SprBucket.shallow);
      expect(sprBucket(5.0), SprBucket.medium);
      expect(sprBucket(6.0), SprBucket.medium);
      expect(sprBucket(10.0), SprBucket.deep);
    });
    test('every bucket has a non-empty label', () {
      for (final b in SprBucket.values) {
        expect(sprBucketLabel(b), isNotEmpty);
      }
    });
  });

  group('boardDynamism', () {
    test('pre-flop, turn-card-less river, and bad lengths are null', () {
      expect(boardDynamism(_cards('Ah Kd')), isNull); // 2 cards
      expect(boardDynamism(_cards('Ah Kd 7c 2s 9h')), isNull); // river, 5 cards
      expect(boardDynamism(const []), isNull);
    });

    test('a dry rainbow flop is static — only the 9 board-pairing cards move it',
        () {
      final d = boardDynamism(_cards('Kc 8d 2h'))!;
      expect(d.unseen, 49);
      expect(d.flushCards, 0); // rainbow → no suit has 2+
      expect(d.straightCards, 0); // K-8-2 shares no straight window
      expect(d.pairCards, 9); // 3 each of K, 8, 2
      expect(d.dynamic, 9); // = pairCards (no overlap)
      expect(d.isDynamic, isFalse); // 9/49 ≈ 0.18 < threshold
    });

    test('a wet two-tone connected flop is dynamic', () {
      // 9♥7♥2♠: 11 hearts advance the flush; ranks 5,6,8,T,J (×4) open a new
      // straight window; 9/7/2 pair (3 each). Union of the three = 34 of 49.
      final d = boardDynamism(_cards('9h 7h 2s'))!;
      expect(d.unseen, 49);
      expect(d.flushCards, 11);
      expect(d.straightCards, 20);
      expect(d.pairCards, 9);
      expect(d.dynamic, 34);
      expect(d.dynamicFraction, closeTo(34 / 49, 1e-9));
      expect(d.isDynamic, isTrue);
    });

    test('a paired rainbow flop is static', () {
      // KsKd5c: only board-pairing cards (2 kings + 3 fives) move it.
      final d = boardDynamism(_cards('Ks Kd 5c'))!;
      expect(d.flushCards, 0);
      expect(d.straightCards, 0);
      expect(d.pairCards, 5);
      expect(d.dynamic, 5);
      expect(d.isDynamic, isFalse);
    });

    test('excluded cards (hero hole) reduce the unseen count to 47', () {
      // Hero holds two cards not on the board → 52 − 3 − 2 = 47.
      final d = boardDynamism(_cards('Kc 8d 2h'),
          excluded: _cards('As Ad').toSet())!;
      expect(d.unseen, 47);
    });

    test('a 4-card turn board considers 48 unseen cards', () {
      final d = boardDynamism(_cards('Kc 8d 2h 4s'))!;
      expect(d.street, 4);
      expect(d.unseen, 48);
    });

    test('subset counts never undercut the union, union never exceeds their sum',
        () {
      for (final b in ['9h 7h 2s', 'Kc 8d 2h', 'Ah Kh 4h', 'Ks Kd 5c']) {
        final d = boardDynamism(_cards(b))!;
        expect(d.dynamic, greaterThanOrEqualTo(d.flushCards), reason: b);
        expect(d.dynamic, greaterThanOrEqualTo(d.pairCards), reason: b);
        expect(d.dynamic, greaterThanOrEqualTo(d.straightCards), reason: b);
        expect(d.dynamic,
            lessThanOrEqualTo(d.flushCards + d.straightCards + d.pairCards),
            reason: b);
        expect(d.dynamic, lessThanOrEqualTo(d.unseen), reason: b);
      }
    });
  });

  group('equitySpread', () {
    test('empty input is null', () {
      expect(equitySpread(const []), isNull);
    });

    test('a single value has zero spread', () {
      final s = equitySpread([0.42])!;
      expect(s.n, 1);
      expect(s.min, 0.42);
      expect(s.max, 0.42);
      expect(s.mean, 0.42);
      expect(s.stdev, 0.0);
      expect(s.range, 0.0);
    });

    test('a constant list has zero standard deviation', () {
      final s = equitySpread([0.5, 0.5, 0.5])!;
      expect(s.stdev, closeTo(0.0, 1e-12));
      expect(s.range, 0.0);
    });

    test('computes min, max, mean, range and population stdev', () {
      final s = equitySpread([0.2, 0.4, 0.6])!;
      expect(s.n, 3);
      expect(s.min, 0.2);
      expect(s.max, 0.6);
      expect(s.mean, closeTo(0.4, 1e-12));
      expect(s.range, closeTo(0.4, 1e-12));
      // population stdev = sqrt(((0.2)²+0+(0.2)²)/3) = sqrt(0.08/3)
      expect(s.stdev, closeTo(0.163299, 1e-5));
    });
  });
}
