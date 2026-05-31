import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/hand_model.dart';

void main() {
  // ── HandAction round-trip ────────────────────────────────────────────────────

  group('HandAction.fromJson / toJson', () {
    test('round-trips a fold action', () {
      const action = HandAction(seat: 2, type: ActionType.fold);
      final result = HandAction.fromJson(action.toJson());
      expect(result.seat, equals(action.seat));
      expect(result.type, equals(action.type));
      expect(result.amount, isNull);
      expect(result.isAllIn, isFalse);
      expect(result.isOpeningBet, isFalse);
    });

    test('round-trips a raise action with amount', () {
      const action = HandAction(seat: 0, type: ActionType.raise, amount: 150);
      final result = HandAction.fromJson(action.toJson());
      expect(result.amount, equals(150));
      expect(result.type, equals(ActionType.raise));
    });

    test('round-trips an all-in action', () {
      const action = HandAction(
          seat: 3, type: ActionType.allIn, amount: 800, isAllIn: true);
      final result = HandAction.fromJson(action.toJson());
      expect(result.isAllIn, isTrue);
      expect(result.amount, equals(800));
    });

    test('round-trips an opening-bet flag', () {
      const action = HandAction(
          seat: 1, type: ActionType.raise, amount: 20, isOpeningBet: true);
      final result = HandAction.fromJson(action.toJson());
      expect(result.isOpeningBet, isTrue);
    });

    test('round-trips a post action', () {
      const action = HandAction(seat: 1, type: ActionType.post, amount: 2);
      final result = HandAction.fromJson(action.toJson());
      expect(result.type, equals(ActionType.post));
      expect(result.amount, equals(2));
    });
  });

  // ── HandAction label ─────────────────────────────────────────────────────────

  group('HandAction.label', () {
    test('fold label', () {
      expect(
          const HandAction(seat: 0, type: ActionType.fold).label, equals('FOLD'));
    });

    test('check label', () {
      expect(
          const HandAction(seat: 0, type: ActionType.check).label,
          equals('CHECK'));
    });

    test('call label includes amount', () {
      expect(
          const HandAction(seat: 0, type: ActionType.call, amount: 10).label,
          equals('CALL \$10'));
    });

    test('raise label', () {
      expect(
          const HandAction(seat: 0, type: ActionType.raise, amount: 40).label,
          equals('RAISE \$40'));
    });

    test('opening bet label', () {
      expect(
          const HandAction(
                  seat: 0,
                  type: ActionType.raise,
                  amount: 8,
                  isOpeningBet: true)
              .label,
          equals('BET \$8'));
    });

    test('all-in label on raise', () {
      expect(
          const HandAction(
                  seat: 0, type: ActionType.raise, amount: 500, isAllIn: true)
              .label,
          equals('ALL-IN \$500'));
    });
  });

  // ── StreetData round-trip ────────────────────────────────────────────────────

  group('StreetData.fromJson / toJson', () {
    test('round-trips preflop with no community cards', () {
      const street = StreetData(
        street: Street.preflop,
        actions: [
          HandAction(seat: 2, type: ActionType.raise, amount: 15),
          HandAction(seat: 3, type: ActionType.fold),
        ],
      );
      final result = StreetData.fromJson(street.toJson());
      expect(result.street, equals(Street.preflop));
      expect(result.communityCards, isEmpty);
      expect(result.actions.length, equals(2));
      expect(result.actions[0].type, equals(ActionType.raise));
    });

    test('round-trips flop with community cards', () {
      const street = StreetData(
        street: Street.flop,
        communityCards: ['Ah', 'Kd', '7c'],
        actions: [
          HandAction(seat: 1, type: ActionType.check),
        ],
      );
      final result = StreetData.fromJson(street.toJson());
      expect(result.communityCards, equals(['Ah', 'Kd', '7c']));
      expect(result.street, equals(Street.flop));
    });
  });

  // ── TableSetup round-trip ────────────────────────────────────────────────────

  group('TableSetup.fromJson / toJson', () {
    test('round-trips 6-max setup', () {
      const setup = TableSetup(
        numSeats: 6,
        buttonSeat: 0,
        heroSeat: 2,
        smallBlind: 1,
        bigBlind: 2,
      );
      final result = TableSetup.fromJson(setup.toJson());
      expect(result.numSeats, equals(6));
      expect(result.buttonSeat, equals(0));
      expect(result.heroSeat, equals(2));
      expect(result.smallBlind, equals(1));
      expect(result.bigBlind, equals(2));
      expect(result.straddle, isNull);
      expect(result.ante, isNull);
    });

    test('round-trips setup with straddle and ante', () {
      const setup = TableSetup(
        numSeats: 9,
        buttonSeat: 5,
        heroSeat: 8,
        smallBlind: 5,
        bigBlind: 10,
        straddle: 20,
        ante: 2,
      );
      final result = TableSetup.fromJson(setup.toJson());
      expect(result.straddle, equals(20));
      expect(result.ante, equals(2));
    });

    test('sbSeat and bbSeat are computed correctly', () {
      const setup = TableSetup(
          numSeats: 6,
          buttonSeat: 4,
          heroSeat: 0,
          smallBlind: 1,
          bigBlind: 2);
      expect(setup.sbSeat, equals(5));
      expect(setup.bbSeat, equals(0));
    });
  });

  // ── HandPlayer round-trip ────────────────────────────────────────────────────

  group('HandPlayer.fromJson / toJson', () {
    test('round-trips hero with hole cards', () {
      const player = HandPlayer(
        seatIndex: 2,
        name: 'Hero',
        startingStack: 400,
        isHero: true,
        holeCards: ['As', 'Kh'],
      );
      final result = HandPlayer.fromJson(player.toJson());
      expect(result.seatIndex, equals(2));
      expect(result.name, equals('Hero'));
      expect(result.startingStack, equals(400));
      expect(result.isHero, isTrue);
      expect(result.holeCards, equals(['As', 'Kh']));
    });

    test('round-trips villain without hole cards', () {
      const player = HandPlayer(
          seatIndex: 4, name: 'Villain', startingStack: 300, isHero: false);
      final result = HandPlayer.fromJson(player.toJson());
      expect(result.holeCards, isNull);
      expect(result.isHero, isFalse);
    });
  });

  // ── PokerHand round-trip ─────────────────────────────────────────────────────

  group('PokerHand.fromJson / toJson', () {
    PokerHand makeHand({String? sessionId, String? notes, String? stage}) {
      return PokerHand(
        id: 'hand-1',
        userId: 'user-1',
        sessionId: sessionId,
        playedAt: DateTime(2026, 5, 31, 20, 0, 0),
        tableSetup: const TableSetup(
          numSeats: 6,
          buttonSeat: 0,
          heroSeat: 2,
          smallBlind: 1,
          bigBlind: 2,
        ),
        players: const [
          HandPlayer(
              seatIndex: 2,
              name: 'Hero',
              startingStack: 200,
              isHero: true,
              holeCards: ['Ac', 'Kd']),
          HandPlayer(
              seatIndex: 4, name: 'Villain', startingStack: 150, isHero: false),
        ],
        streets: const [
          StreetData(
            street: Street.preflop,
            actions: [
              HandAction(seat: 2, type: ActionType.raise, amount: 8),
              HandAction(seat: 4, type: ActionType.call, amount: 8),
            ],
          ),
        ],
        notes: notes,
        tournamentStage: stage,
      );
    }

    test('round-trips a basic hand', () {
      final hand = makeHand();
      final result = PokerHand.fromJson(hand.toJson());
      expect(result.id, equals('hand-1'));
      expect(result.userId, equals('user-1'));
      expect(result.sessionId, isNull);
      expect(result.playedAt, equals(DateTime(2026, 5, 31, 20, 0, 0)));
      expect(result.players.length, equals(2));
      expect(result.streets.length, equals(1));
      expect(result.notes, isNull);
      expect(result.tournamentStage, isNull);
    });

    test('round-trips optional fields when set', () {
      final hand =
          makeHand(sessionId: 'sess-abc', notes: 'Bluff gone wrong', stage: 'Final Table');
      final result = PokerHand.fromJson(hand.toJson());
      expect(result.sessionId, equals('sess-abc'));
      expect(result.notes, equals('Bluff gone wrong'));
      expect(result.tournamentStage, equals('Final Table'));
    });

    test('hero getter returns the hero player', () {
      final hand = makeHand();
      expect(hand.hero?.name, equals('Hero'));
      expect(hand.hero?.isHero, isTrue);
    });

    test('allCommunityCards aggregates across streets', () {
      final hand = PokerHand(
        id: 'h2',
        userId: 'u1',
        playedAt: DateTime.now(),
        tableSetup: const TableSetup(
            numSeats: 6,
            buttonSeat: 0,
            heroSeat: 1,
            smallBlind: 1,
            bigBlind: 2),
        players: const [],
        streets: const [
          StreetData(street: Street.preflop, actions: []),
          StreetData(
              street: Street.flop,
              communityCards: ['2h', '7d', 'Ks'],
              actions: []),
          StreetData(
              street: Street.turn, communityCards: ['9c'], actions: []),
        ],
      );
      expect(hand.allCommunityCards, equals(['2h', '7d', 'Ks', '9c']));
    });

    test('streetReached returns correct street name', () {
      final base = makeHand();
      expect(base.streetReached, equals('Pre-flop'));

      final flop = PokerHand(
        id: 'h', userId: 'u', playedAt: DateTime.now(),
        tableSetup: base.tableSetup, players: const [],
        streets: const [
          StreetData(street: Street.preflop, actions: []),
          StreetData(street: Street.flop, communityCards: ['Ah','2d','3c'], actions: []),
        ],
      );
      expect(flop.streetReached, equals('Flop'));
    });
  });
}
