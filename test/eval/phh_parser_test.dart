import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/hand_model.dart';

import '../../tool/eval/phh_parser.dart';

// The Dwan/Ivey 2009 hand (3-handed cash, antes) — exercises blind posts, a
// preflop 3-bet, an opening flop bet, a turn raise-war, and a stack-capped
// all-in call.
const _dwan = '''
variant = "NT"
ante_trimming_status = true
antes = [500, 500, 500]
blinds_or_straddles = [1000, 2000, 0]
min_bet = 2000
starting_stacks = [1125600, 2000000, 553500]
actions = [
  "d dh p1 Ac2d",
  "d dh p2 ????",
  "d dh p3 7h6h",
  "p3 cbr 7000",
  "p1 cbr 23000",
  "p2 f",
  "p3 cc",
  "d db Jc3d5c",
  "p1 cbr 35000",
  "p3 cc",
  "d db 4h",
  "p1 cbr 90000",
  "p3 cbr 232600",
  "p1 cbr 1067100",
  "p3 cc",
  "p1 sm Ac2d",
  "p3 sm 7h6h",
  "d db Jh",
]
players = ["Phil Ivey", "Patrik Antonius", "Tom Dwan"]
''';

// A Pluribus 6-max hand (single-line actions array, no antes, a 'T' rank and a
// flushy board) — the benchmark's primary source shape.
const _pluribus = '''
variant = 'NT'
ante_trimming_status = true
antes = [0, 0, 0, 0, 0, 0]
blinds_or_straddles = [50, 100, 0, 0, 0, 0]
min_bet = 100
starting_stacks = [10000, 10000, 10000, 10000, 10000, 10000]
actions = ['d dh p1 Qh5c', 'd dh p2 9h6h', 'd dh p3 KcJh', 'd dh p4 8hQc', 'd dh p5 7hKh', 'd dh p6 Ks3c', 'p3 cbr 210', 'p4 f', 'p5 f', 'p6 f', 'p1 f', 'p2 cc', 'd db 7s9cTc', 'p2 cc', 'p3 cbr 235', 'p2 cc', 'd db 2c', 'p2 cc', 'p3 cbr 600', 'p2 f']
hand = 1
players = ['MrBlonde', 'MrWhite', 'MrPink', 'MrBrown', 'Pluribus', 'MrBlue']
''';

void main() {
  group('PHH parser', () {
    test('3-handed cash: button, blinds, posts, all-in cap', () {
      final h = parsePhhText(_dwan);
      expect(h.numSeats, 3);
      expect(h.knownHolePlayers, {1, 3}); // p2 is ????

      final hand = phhToPokerHand(h,
          heroPlayer: 3, id: 't', playedAt: DateTime.utc(2026, 1, 1));

      // p1=SB, p2=BB, p3=BTN (no-blind seat) for 3-handed.
      expect(hand.tableSetup.buttonSeat, 2);
      expect(hand.tableSetup.heroSeat, 2);
      expect(hand.tableSetup.smallBlind, 1000);
      expect(hand.tableSetup.bigBlind, 2000);
      expect(hand.hero!.holeCards, ['7h', '6h']);
      // Villain cards are dropped (result-independence).
      expect(hand.players[0].holeCards, isNull);

      final pre = hand.streets.firstWhere((s) => s.street == Street.preflop);
      // Posts seeded first, then the recorded action.
      expect(pre.actions[0].type, ActionType.post);
      expect(pre.actions[0].amount, 1000);
      expect(pre.actions[1].amount, 2000);

      // Flop bet flagged as an opening bet.
      final flop = hand.streets.firstWhere((s) => s.street == Street.flop);
      final flopBet = flop.actions.firstWhere((a) => a.type == ActionType.raise);
      expect(flopBet.isOpeningBet, isTrue);

      // Hero's turn call is stack-capped and flagged all-in. His 500 ante is
      // folded into his committed chips (it leaves the stack before betting),
      // so the all-in call is 553500 − 500 ante − 23000 pre − 35000 flop −
      // 232600 turn-bet = 262400, i.e. a cumulative turn total of 495000.
      final turn = hand.streets.firstWhere((s) => s.street == Street.turn);
      final heroCall =
          turn.actions.lastWhere((a) => a.seat == 2 && a.type == ActionType.call);
      expect(heroCall.isAllIn, isTrue);
      expect(heroCall.amount, 495000); // cumulative this street, ante-aware cap
    });

    test('6-max Pluribus: single-line actions, T rank, check/bet/fold', () {
      final h = parsePhhText(_pluribus);
      expect(h.numSeats, 6);
      expect(h.knownHolePlayers, {1, 2, 3, 4, 5, 6});

      final hand = phhToPokerHand(h,
          heroPlayer: 3, id: 't', playedAt: DateTime.utc(2026, 1, 1));
      expect(hand.tableSetup.buttonSeat, 5);
      expect(hand.hero!.holeCards, ['Kc', 'Jh']);
      expect(hand.isTournament, isFalse); // no antes

      final flop = hand.streets.firstWhere((s) => s.street == Street.flop);
      expect(flop.communityCards, ['7s', '9c', 'Tc']);
      // BB checks, hero opens (bet), BB calls.
      expect(flop.actions[0].type, ActionType.check);
      expect(flop.actions[1].type, ActionType.raise);
      expect(flop.actions[1].isOpeningBet, isTrue);
      expect(flop.actions[1].amount, 235);

      final turn = hand.streets.firstWhere((s) => s.street == Street.turn);
      expect(turn.communityCards, ['2c']);
      // BB folds to the turn bet.
      expect(turn.actions.any((a) => a.type == ActionType.fold), isTrue);
    });
  });
}
