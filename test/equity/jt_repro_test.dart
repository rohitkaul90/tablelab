import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';

// Faithful reproduction of the real JT hand:
// 9-max, $2/$5/$10 straddle. Hero UTG+1 (seat 4) raises, CO (seat 8) calls,
// SB (seat 1) calls. Flop Js4d5c: SB check, Hero bet, CO CALL, SB fold.
// Turn 9c: Hero check, CO BET, Hero call. River 2h: Hero check, CO BET, Hero
// call. Hero JdTd = top pair. CO's line is call/bet/bet (NOT bet/bet/bet).

void main() {
  test('JT real-line river equity', () async {
    final hand = PokerHand(
      id: 'jt',
      userId: 'u1',
      playedAt: DateTime(2026, 6, 1),
      tableSetup: const TableSetup(
        numSeats: 9,
        buttonSeat: 0,
        heroSeat: 4,
        smallBlind: 2,
        bigBlind: 5,
        straddle: 10,
      ),
      players: const [
        HandPlayer(
            seatIndex: 4,
            name: 'Hero',
            startingStack: 1500,
            isHero: true,
            holeCards: ['Jd', 'Td']),
        // CO turned over As3s at showdown (the wheel A-2-3-4-5 on the 2h
        // river). The cross-check must IGNORE these recorded cards and model CO
        // by range — otherwise river equity collapses to the result (0%).
        HandPlayer(
            seatIndex: 8,
            name: 'CO',
            startingStack: 1000,
            holeCards: ['As', '3s']),
        HandPlayer(seatIndex: 1, name: 'SB', startingStack: 1000),
      ],
      streets: const [
        StreetData(street: Street.preflop, actions: [
          HandAction(seat: 1, type: ActionType.post, amount: 2),
          HandAction(seat: 2, type: ActionType.post, amount: 5),
          HandAction(seat: 3, type: ActionType.postStraddle, amount: 10),
          HandAction(seat: 4, type: ActionType.raise, amount: 35),
          HandAction(seat: 8, type: ActionType.call, amount: 35),
          HandAction(seat: 1, type: ActionType.call, amount: 35),
        ]),
        StreetData(street: Street.flop, communityCards: ['Js', '4d', '5c'], actions: [
          HandAction(seat: 1, type: ActionType.check),
          HandAction(seat: 4, type: ActionType.raise, amount: 45, isOpeningBet: true),
          HandAction(seat: 8, type: ActionType.call, amount: 45),
          HandAction(seat: 1, type: ActionType.fold),
        ]),
        StreetData(street: Street.turn, communityCards: ['9c'], actions: [
          HandAction(seat: 4, type: ActionType.check),
          HandAction(seat: 8, type: ActionType.raise, amount: 100, isOpeningBet: true),
          HandAction(seat: 4, type: ActionType.call, amount: 100),
        ]),
        StreetData(street: Street.river, communityCards: ['2h'], actions: [
          HandAction(seat: 4, type: ActionType.check),
          HandAction(seat: 8, type: ActionType.raise, amount: 300, isOpeningBet: true),
          HandAction(seat: 4, type: ActionType.call, amount: 300),
        ]),
      ],
      isTournament: false,
    );

    final check = await computeHandEquityCheck(hand, iterations: 20000);
    expect(check, isNotNull);
    final river = check!.streets.firstWhere((s) => s.street == Street.river);
    // Top pair vs CO's call/bet/bet line: a polarized betting range keeps a
    // bluff tail (busted clubs, missed straight draws, ace-highs) that JdTd
    // beats, so river equity must be materially above zero — NOT the ~0% the
    // old value-only narrowing produced.
    expect(river.heroEquity, greaterThan(0.20),
        reason: 'JdTd top pair must beat CO bluffs on the river '
            '(was ${river.heroEquity})');
    expect(river.heroEquity, lessThan(0.55),
        reason: 'but it is only a bluff-catcher, not a clear favorite');
  });
}
