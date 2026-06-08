import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/hand_model.dart';
import 'package:tablelab/models/hand_filter.dart';

PokerHand _hand({
  int sb = 1,
  int bb = 2,
  int numSeats = 6,
  int heroSeat = 5,
  bool isTournament = false,
  DateTime? playedAt,
  List<StreetData>? streets,
}) {
  return PokerHand(
    id: 'h',
    userId: 'u',
    playedAt: playedAt ?? DateTime(2026, 6, 1, 20),
    tableSetup: TableSetup(
      numSeats: numSeats,
      buttonSeat: 0,
      heroSeat: heroSeat,
      smallBlind: sb,
      bigBlind: bb,
    ),
    players: const [],
    streets: streets ??
        const [
          StreetData(street: Street.preflop, actions: [
            HandAction(seat: 0, type: ActionType.raise, amount: 50),
            HandAction(seat: 1, type: ActionType.call, amount: 50),
          ]),
        ],
    isTournament: isTournament,
  );
}

void main() {
  group('HandFilter.isEmpty', () {
    test('default is empty', () => expect(const HandFilter().isEmpty, isTrue));
    test('any set field is not empty',
        () => expect(const HandFilter(gameType: 'cash').isEmpty, isFalse));
  });

  group('HandFilter helpers', () {
    test('handStakesKey is smallBlind/bigBlind', () {
      expect(handStakesKey(_hand(sb: 5, bb: 10)), equals('5/10'));
    });
    test('handHeroPosition uses hero seat (CO at seat 5 / 6-max)', () {
      expect(handHeroPosition(_hand(numSeats: 6, heroSeat: 5)), equals('CO'));
    });
  });

  group('HandFilter.matches', () {
    test('game type filters on isTournament', () {
      expect(const HandFilter(gameType: 'cash').matches(_hand()), isTrue);
      expect(const HandFilter(gameType: 'tournament').matches(_hand()), isFalse);
      expect(
          const HandFilter(gameType: 'tournament')
              .matches(_hand(isTournament: true)),
          isTrue);
    });

    test('minimum pot is measured in big blinds', () {
      // pot 100 at bb 2 => 50bb
      expect(const HandFilter(minPotBb: 50).matches(_hand()), isTrue);
      expect(const HandFilter(minPotBb: 100).matches(_hand()), isFalse);
      // same 100-chip pot at bb 1 => 100bb
      expect(const HandFilter(minPotBb: 100).matches(_hand(bb: 1)), isTrue);
    });

    test('stakes matches the blind key', () {
      expect(const HandFilter(stakes: '1/2').matches(_hand()), isTrue);
      expect(const HandFilter(stakes: '5/10').matches(_hand()), isFalse);
    });

    test('table size matches seat count', () {
      expect(const HandFilter(tableSize: 6).matches(_hand()), isTrue);
      expect(const HandFilter(tableSize: 9).matches(_hand()), isFalse);
    });

    test('hero position matches', () {
      expect(const HandFilter(heroPosition: 'CO').matches(_hand()), isTrue);
      expect(const HandFilter(heroPosition: 'BTN').matches(_hand()), isFalse);
    });

    test('street reached matches', () {
      expect(const HandFilter(streetReached: 'Pre-flop').matches(_hand()), isTrue);
      expect(const HandFilter(streetReached: 'Flop').matches(_hand()), isFalse);
    });

    test('date range is inclusive', () {
      final h = _hand(playedAt: DateTime(2026, 6, 1, 20));
      expect(const HandFilter(dateFrom: '2026-06-01').matches(h), isTrue);
      expect(const HandFilter(dateTo: '2026-06-01').matches(h), isTrue);
      expect(const HandFilter(dateFrom: '2026-06-02').matches(h), isFalse);
      expect(const HandFilter(dateTo: '2026-05-31').matches(h), isFalse);
    });

    test('criteria are AND-ed together', () {
      const f = HandFilter(gameType: 'cash', minPotBb: 50, tableSize: 6);
      expect(f.matches(_hand()), isTrue);
      // wrong game type fails the whole filter even though pot/size match
      expect(f.matches(_hand(isTournament: true)), isFalse);
    });
  });
}
