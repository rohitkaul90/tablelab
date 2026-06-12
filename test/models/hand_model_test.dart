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

    test('finalPot sums each seat\'s max contribution (single street)', () {
      // makeHand preflop: seat 2 raises 8, seat 4 calls 8 -> pot 16
      expect(makeHand().finalPot, equals(16));
    });

    test('finalPot accumulates across streets', () {
      final hand = PokerHand(
        id: 'h', userId: 'u', playedAt: DateTime(2026, 1, 1),
        tableSetup: const TableSetup(
            numSeats: 6, buttonSeat: 0, heroSeat: 1, smallBlind: 1, bigBlind: 2),
        players: const [],
        streets: const [
          StreetData(street: Street.preflop, actions: [
            HandAction(seat: 0, type: ActionType.raise, amount: 10),
            HandAction(seat: 1, type: ActionType.call, amount: 10),
          ]),
          StreetData(street: Street.flop, communityCards: ['Ah', 'Kd', '7c'], actions: [
            HandAction(seat: 1, type: ActionType.raise, amount: 15, isOpeningBet: true),
            HandAction(seat: 0, type: ActionType.call, amount: 15),
          ]),
        ],
      );
      // preflop 10+10=20, flop 15+15=30 -> 50
      expect(hand.finalPot, equals(50));
    });

    test('isTournament round-trips explicitly', () {
      final hand = PokerHand(
        id: 'h', userId: 'u', playedAt: DateTime(2026, 1, 1),
        tableSetup: const TableSetup(
            numSeats: 9, buttonSeat: 0, heroSeat: 1, smallBlind: 100, bigBlind: 200),
        players: const [], streets: const [],
        isTournament: true,
      );
      expect(PokerHand.fromJson(hand.toJson()).isTournament, isTrue);
    });

    test('legacy hand (no isTournament) infers tournament from a stage', () {
      final json = {
        'id': 'h', 'userId': 'u', 'playedAt': '2026-01-01T00:00:00.000',
        'tableSetup': {
          'numSeats': 9, 'buttonSeat': 0, 'heroSeat': 1,
          'smallBlind': 100, 'bigBlind': 200,
        },
        'players': [], 'streets': [],
        'tournamentStage': 'Final Table',
      };
      expect(PokerHand.fromJson(json).isTournament, isTrue);
    });

    test('legacy hand (no isTournament) infers tournament from an ante', () {
      final json = {
        'id': 'h', 'userId': 'u', 'playedAt': '2026-01-01T00:00:00.000',
        'tableSetup': {
          'numSeats': 9, 'buttonSeat': 0, 'heroSeat': 1,
          'smallBlind': 100, 'bigBlind': 200, 'ante': 25,
        },
        'players': [], 'streets': [],
      };
      expect(PokerHand.fromJson(json).isTournament, isTrue);
    });

    test('legacy cash hand (no stage, no ante) infers cash', () {
      final json = {
        'id': 'h', 'userId': 'u', 'playedAt': '2026-01-01T00:00:00.000',
        'tableSetup': {
          'numSeats': 6, 'buttonSeat': 0, 'heroSeat': 1,
          'smallBlind': 1, 'bigBlind': 2,
        },
        'players': [], 'streets': [],
      };
      expect(PokerHand.fromJson(json).isTournament, isFalse);
    });

    test('isQuickEntry round-trips when true', () {
      final hand = PokerHand(
        id: 'h', userId: 'u', playedAt: DateTime(2026, 1, 1),
        tableSetup: const TableSetup(
            numSeats: 6, buttonSeat: 0, heroSeat: 2, smallBlind: 1, bigBlind: 2),
        players: const [], streets: const [],
        isQuickEntry: true,
      );
      final json = hand.toJson();
      expect(json['isQuickEntry'], isTrue);
      expect(PokerHand.fromJson(json).isQuickEntry, isTrue);
    });

    test('isQuickEntry is omitted from JSON when false', () {
      expect(makeHand().toJson().containsKey('isQuickEntry'), isFalse);
    });

    test('legacy hand without isQuickEntry parses as false', () {
      final json = {
        'id': 'h', 'userId': 'u', 'playedAt': '2026-01-01T00:00:00.000',
        'tableSetup': {
          'numSeats': 6, 'buttonSeat': 0, 'heroSeat': 1,
          'smallBlind': 1, 'bigBlind': 2,
        },
        'players': [], 'streets': [],
      };
      expect(PokerHand.fromJson(json).isQuickEntry, isFalse);
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

    test('streetReached returns Turn and River for deeper hands', () {
      final base = makeHand();
      StreetData s(Street st) => StreetData(street: st, actions: const []);

      final turn = PokerHand(
        id: 'h', userId: 'u', playedAt: DateTime(2026, 1, 1),
        tableSetup: base.tableSetup, players: const [],
        streets: [s(Street.preflop), s(Street.flop), s(Street.turn)],
      );
      expect(turn.streetReached, equals('Turn'));

      final river = PokerHand(
        id: 'h', userId: 'u', playedAt: DateTime(2026, 1, 1),
        tableSetup: base.tableSetup, players: const [],
        streets: [
          s(Street.preflop), s(Street.flop), s(Street.turn), s(Street.river)
        ],
      );
      expect(river.streetReached, equals('River'));
    });
  });

  // ── Street.label extension ───────────────────────────────────────────────────

  group('StreetLabel.label', () {
    test('returns the display label for every street', () {
      expect(Street.preflop.label, equals('Pre-flop'));
      expect(Street.flop.label, equals('Flop'));
      expect(Street.turn.label, equals('Turn'));
      expect(Street.river.label, equals('River'));
    });
  });

  // ── HandAction.label — remaining branches ────────────────────────────────────

  group('HandAction.label — allIn / post / straddle', () {
    test('dedicated all-in action type', () {
      expect(
          const HandAction(seat: 0, type: ActionType.allIn, amount: 1200).label,
          equals('ALL-IN \$1200'));
    });

    test('post (blind) label', () {
      expect(const HandAction(seat: 1, type: ActionType.post, amount: 2).label,
          equals('POST \$2'));
    });

    test('straddle label', () {
      expect(
          const HandAction(seat: 3, type: ActionType.postStraddle, amount: 4)
              .label,
          equals('STRADDLE \$4'));
    });

    test('null amount falls back to 0 in label', () {
      expect(const HandAction(seat: 0, type: ActionType.call).label,
          equals('CALL \$0'));
    });
  });

  // ── HandPlayer.copyWith ──────────────────────────────────────────────────────

  group('HandPlayer.copyWith', () {
    const base = HandPlayer(
        seatIndex: 2, name: 'Hero', startingStack: 400, isHero: true);

    test('overrides holeCards while preserving other fields', () {
      final updated = base.copyWith(holeCards: ['As', 'Kh']);
      expect(updated.holeCards, equals(['As', 'Kh']));
      expect(updated.seatIndex, equals(2));
      expect(updated.name, equals('Hero'));
      expect(updated.startingStack, equals(400));
      expect(updated.isHero, isTrue);
    });

    test('preserves existing holeCards when none provided', () {
      const withCards = HandPlayer(
          seatIndex: 1,
          name: 'Hero',
          startingStack: 200,
          holeCards: ['Qd', 'Qs']);
      final copy = withCards.copyWith();
      expect(copy.holeCards, equals(['Qd', 'Qs']));
    });
  });

  // ── TableSetup — straddleSeat / positionName / action order ───────────────────

  group('TableSetup.straddleSeat', () {
    test('returns -1 when no straddle', () {
      const setup = TableSetup(
          numSeats: 6,
          buttonSeat: 0,
          heroSeat: 2,
          smallBlind: 1,
          bigBlind: 2);
      expect(setup.straddleSeat, equals(-1));
    });

    test('seat after BB when straddle present (with wraparound)', () {
      const setup = TableSetup(
          numSeats: 6,
          buttonSeat: 4,
          heroSeat: 0,
          smallBlind: 1,
          bigBlind: 2,
          straddle: 4);
      // (4 + 3) % 6 = 1
      expect(setup.straddleSeat, equals(1));
    });
  });

  group('TableSetup.positionName', () {
    test('6-max names relative to button', () {
      const setup = TableSetup(
          numSeats: 6,
          buttonSeat: 0,
          heroSeat: 2,
          smallBlind: 1,
          bigBlind: 2);
      expect(setup.positionName(0), equals('BTN'));
      expect(setup.positionName(1), equals('SB'));
      expect(setup.positionName(2), equals('BB'));
      expect(setup.positionName(3), equals('UTG'));
      expect(setup.positionName(4), equals('HJ'));
      expect(setup.positionName(5), equals('CO'));
    });

    test('straddle seat overrides position name with STR', () {
      const setup = TableSetup(
          numSeats: 6,
          buttonSeat: 0,
          heroSeat: 2,
          smallBlind: 1,
          bigBlind: 2,
          straddle: 3);
      expect(setup.positionName(3), equals('STR'));
    });

    test('9-max names use the wide table labels', () {
      const setup = TableSetup(
          numSeats: 9,
          buttonSeat: 0,
          heroSeat: 4,
          smallBlind: 1,
          bigBlind: 2);
      expect(setup.positionName(0), equals('BTN'));
      expect(setup.positionName(4), equals('UTG+1'));
      expect(setup.positionName(8), equals('CO'));
    });

    test('falls back to generic Pn when seat is beyond label list', () {
      const setup = TableSetup(
          numSeats: 10,
          buttonSeat: 0,
          heroSeat: 1,
          smallBlind: 1,
          bigBlind: 2);
      // off = 9, labels only cover 0..8 → generic fallback
      expect(setup.positionName(9), equals('P10'));
    });
  });

  group('TableSetup action order', () {
    const setup = TableSetup(
        numSeats: 6, buttonSeat: 0, heroSeat: 2, smallBlind: 1, bigBlind: 2);
    final active = [0, 1, 2, 3, 4, 5];

    test('preflopOrder starts UTG (button + 3) without straddle', () {
      expect(setup.preflopOrder(active), equals([3, 4, 5, 0, 1, 2]));
    });

    test('preflopOrder starts one later when a straddle is posted', () {
      const straddled = TableSetup(
          numSeats: 6,
          buttonSeat: 0,
          heroSeat: 2,
          smallBlind: 1,
          bigBlind: 2,
          straddle: 4);
      expect(straddled.preflopOrder(active), equals([4, 5, 0, 1, 2, 3]));
    });

    test('preflopOrder respects the active filter', () {
      expect(setup.preflopOrder([0, 2, 4]), equals([4, 0, 2]));
    });

    test('postflopOrder starts at SB (button + 1)', () {
      expect(setup.postflopOrder(active), equals([1, 2, 3, 4, 5, 0]));
    });

    test('postflopOrder respects the active filter', () {
      expect(setup.postflopOrder([0, 3, 5]), equals([3, 5, 0]));
    });
  });

  // ── TableSetup — heads-up and variable table sizes ───────────────────────────

  group('TableSetup.positionLabels (static)', () {
    test('covers heads-up through 9-max with the right count', () {
      for (var n = 2; n <= 9; n++) {
        expect(TableSetup.positionLabels(n).length, equals(n),
            reason: '$n-handed should have $n labels');
        expect(TableSetup.positionLabels(n).first, equals('BTN'));
      }
    });

    test('heads-up is BTN/BB — the button posts the small blind', () {
      expect(TableSetup.positionLabels(2), equals(['BTN', 'BB']));
    });

    test('unknown sizes fall back to generic labels', () {
      final labels = TableSetup.positionLabels(11);
      expect(labels.length, equals(11));
      expect(labels.first, equals('BTN'));
      expect(labels[1], equals('P2'));
    });
  });

  group('TableSetup heads-up (2 seats)', () {
    const buttonZero = TableSetup(
        numSeats: 2, buttonSeat: 0, heroSeat: 0, smallBlind: 1, bigBlind: 2);

    test('button posts the small blind; the other seat is the big blind', () {
      expect(buttonZero.sbSeat, equals(0));
      expect(buttonZero.bbSeat, equals(1));
    });

    test('position names', () {
      expect(buttonZero.positionName(0), equals('BTN'));
      expect(buttonZero.positionName(1), equals('BB'));
    });

    test('SB (button) acts first preflop, BB acts first postflop', () {
      expect(buttonZero.preflopOrder([0, 1]), equals([0, 1]));
      expect(buttonZero.postflopOrder([0, 1]), equals([1, 0]));
    });

    test('blinds and order rotate with the button seat', () {
      const buttonOne = TableSetup(
          numSeats: 2, buttonSeat: 1, heroSeat: 0, smallBlind: 1, bigBlind: 2);
      expect(buttonOne.sbSeat, equals(1));
      expect(buttonOne.bbSeat, equals(0));
      expect(buttonOne.positionName(1), equals('BTN'));
      expect(buttonOne.positionName(0), equals('BB'));
      expect(buttonOne.preflopOrder([0, 1]), equals([1, 0]));
      expect(buttonOne.postflopOrder([0, 1]), equals([0, 1]));
    });
  });

  group('TableSetup intermediate sizes', () {
    test('3-handed: BTN acts first preflop, SB first postflop', () {
      const setup = TableSetup(
          numSeats: 3, buttonSeat: 0, heroSeat: 0, smallBlind: 1, bigBlind: 2);
      expect(setup.positionName(0), equals('BTN'));
      expect(setup.positionName(1), equals('SB'));
      expect(setup.positionName(2), equals('BB'));
      expect(setup.preflopOrder([0, 1, 2]), equals([0, 1, 2]));
      expect(setup.postflopOrder([0, 1, 2]), equals([1, 2, 0]));
    });

    test('8-max position labels', () {
      const setup = TableSetup(
          numSeats: 8, buttonSeat: 0, heroSeat: 0, smallBlind: 1, bigBlind: 2);
      expect(setup.positionName(3), equals('UTG'));
      expect(setup.positionName(5), equals('MP'));
      expect(setup.positionName(6), equals('HJ'));
      expect(setup.positionName(7), equals('CO'));
    });
  });
}
