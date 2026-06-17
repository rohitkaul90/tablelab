import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';

import '../../tool/eval/forced_decision.dart';

// ── Builders ──────────────────────────────────────────────────────────────────
// Hero is always seat 0. Amounts are CUMULATIVE per-street totals (the model's
// convention). Equity is stubbed directly — no Monte-Carlo — so the pot-odds
// re-derivation is tested deterministically.

HandPlayer _hero(int stack) => HandPlayer(
    seatIndex: 0, name: 'Hero', startingStack: stack, isHero: true,
    holeCards: const ['Ah', 'Kh']);
HandPlayer _villain(int seat, int stack) =>
    HandPlayer(seatIndex: seat, name: 'V$seat', startingStack: stack);

HandAction _raise(int seat, int amt, {bool opening = false, bool allIn = false}) =>
    HandAction(seat: seat, type: ActionType.raise, amount: amt, isOpeningBet: opening, isAllIn: allIn);
HandAction _call(int seat, int amt, {bool allIn = false}) =>
    HandAction(seat: seat, type: ActionType.call, amount: amt, isAllIn: allIn);
HandAction _check(int seat) => HandAction(seat: seat, type: ActionType.check);
HandAction _fold(int seat) => HandAction(seat: seat, type: ActionType.fold);

StreetData _street(Street s, List<HandAction> acts) =>
    StreetData(street: s, communityCards: const [], actions: acts);

PokerHand _hand(List<HandPlayer> players, List<StreetData> streets) => PokerHand(
      id: 't', userId: 't', playedAt: DateTime.utc(2026, 1, 1),
      tableSetup: TableSetup(
          numSeats: players.length, buttonSeat: 0, heroSeat: 0,
          smallBlind: 1, bigBlind: 2),
      players: players, streets: streets,
    );

HandEquityCheck _equity(Map<Street, double> byStreet) => HandEquityCheck(
      streets: [
        for (final e in byStreet.entries)
          StreetEquityCheck(
              street: e.key, heroEquity: e.value, boardSoFar: const [],
              villainCount: 1, iterations: 1),
      ],
      villains: const [],
      basedOnSynthesizedAction: false,
    );

// A standard heads-up hand that checks to the river, where the river action is
// supplied by the caller. Preflop builds a pot of 200 (each puts in 100).
PokerHand _toRiver(List<HandAction> riverActions, {int heroStack = 1000}) => _hand(
      [_hero(heroStack), _villain(1, 1000)],
      [
        _street(Street.preflop, [_raise(0, 100, opening: true), _call(1, 100)]),
        _street(Street.flop, [_check(0), _check(1)]),
        _street(Street.turn, [_check(0), _check(1)]),
        _street(Street.river, riverActions),
      ],
    );

void main() {
  group('computeForcedDecision', () {
    test('river call, equity >= price → forced call, hero correct', () {
      // River: villain bets 100 into a 200 pot, hero calls → price 100/(300+100)=25%.
      final hand = _toRiver([_raise(1, 100, opening: true), _call(0, 100)]);
      final fd = computeForcedDecision(hand, _equity({Street.river: 0.40}))!;
      expect(fd.street, 'river');
      expect(fd.heroCalled, isTrue);
      expect(fd.requiredPct, 25);
      expect(fd.heroEquityPct, 40);
      expect(fd.forcedAction, 'call');
      expect(fd.heroActionCorrect, isTrue);
    });

    test('river call, equity < price → forced fold, hero (who called) is wrong', () {
      final hand = _toRiver([_raise(1, 100, opening: true), _call(0, 100)]);
      final fd = computeForcedDecision(hand, _equity({Street.river: 0.15}))!;
      expect(fd.requiredPct, 25);
      expect(fd.forcedAction, 'fold');
      expect(fd.heroCalled, isTrue);
      expect(fd.heroActionCorrect, isFalse); // a bad call
    });

    test('boundary: equity == price → call (at-or-above is correct)', () {
      final hand = _toRiver([_raise(1, 100, opening: true), _call(0, 100)]);
      final fd = computeForcedDecision(hand, _equity({Street.river: 0.25}))!;
      expect(fd.requiredPct, 25);
      expect(fd.forcedAction, 'call');
    });

    test('river FOLD that should have been a call → over-fold detected', () {
      final hand = _toRiver([_raise(1, 100, opening: true), _fold(0)]);
      final fd = computeForcedDecision(hand, _equity({Street.river: 0.40}))!;
      expect(fd.heroCalled, isFalse);
      expect(fd.requiredPct, 25);
      expect(fd.forcedAction, 'call'); // 40% >= 25% → call was right
      expect(fd.heroActionCorrect, isFalse); // hero folded → over-fold
    });

    test('turn all-in call closes the action → decisive even off the river', () {
      // Hero (stack 200) is all-in calling a turn bet; the board runs out.
      final hand = _hand(
        [_hero(200), _villain(1, 1000)],
        [
          _street(Street.preflop, [_raise(0, 100, opening: true), _call(1, 100)]),
          _street(Street.flop, [_check(0), _check(1)]),
          _street(Street.turn, [_raise(1, 100, opening: true), _call(0, 100, allIn: true)]),
        ],
      );
      final fd = computeForcedDecision(hand, _equity({Street.turn: 0.30}))!;
      expect(fd.street, 'turn');
      expect(fd.requiredPct, 25);
      expect(fd.forcedAction, 'call');
      expect(fd.heroActionCorrect, isTrue);
    });

    test('uncalled-excess strip: hero calls all-in for less than the bet', () {
      // Pot 200 entering river. Villain bets 200; hero (100 behind) calls all-in
      // for 100. The uncovered 100 is stripped: price = 100/((400-100)+100)=25%,
      // NOT 100/(400+100)=20%.
      final hand = _toRiver(
        [_raise(1, 200, opening: true), _call(0, 100, allIn: true)],
        heroStack: 200,
      );
      final fd = computeForcedDecision(hand, _equity({Street.river: 0.50}))!;
      expect(fd.requiredPct, 25); // strip applied (would be 20 without it)
      expect(fd.forcedAction, 'call');
    });

    test('non-decisive: a flop call with streets to come → null', () {
      final hand = _hand(
        [_hero(1000), _villain(1, 1000)],
        [
          _street(Street.preflop, [_raise(0, 100, opening: true), _call(1, 100)]),
          // Hero calls a flop bet but is not all-in and the hand continues.
          _street(Street.flop, [_raise(1, 100, opening: true), _call(0, 100)]),
          _street(Street.turn, [_check(0), _check(1)]),
          _street(Street.river, [_check(0), _check(1)]),
        ],
      );
      expect(computeForcedDecision(hand, _equity({Street.flop: 0.40})), isNull);
    });

    test('unscorable: decisive street has no equity label → null', () {
      final hand = _toRiver([_raise(1, 100, opening: true), _call(0, 100)]);
      // Equity only modeled for the flop, not the river decision street.
      expect(computeForcedDecision(hand, _equity({Street.flop: 0.40})), isNull);
    });
  });
}
