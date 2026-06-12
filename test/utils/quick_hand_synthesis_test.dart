import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/hand_filter.dart';
import 'package:tablelab/models/hand_model.dart';
import 'package:tablelab/utils/quick_hand_synthesis.dart';

QuickHandInput makeInput({
  List<String> heroCards = const ['As', 'Kd'],
  int numSeats = 6,
  String positionLabel = 'CO',
  int smallBlind = 1,
  int bigBlind = 2,
  Street decisionStreet = Street.preflop,
  List<String> boardCards = const [],
  QuickFacing facing = QuickFacing.openRaise,
  QuickHeroAction heroAction = QuickHeroAction.call,
  QuickPotType potType = QuickPotType.auto,
  double? facingSizeBb,
  double? heroSizeBb,
  double? potBeforeBb,
  double? effStackBb,
  QuickResult? result,
  double? resultAmountBb,
  String? userNote,
  bool isTournament = false,
  String? tournamentStage,
  int? ante,
}) =>
    QuickHandInput(
      heroCards: heroCards,
      numSeats: numSeats,
      positionLabel: positionLabel,
      smallBlind: smallBlind,
      bigBlind: bigBlind,
      decisionStreet: decisionStreet,
      boardCards: boardCards,
      facing: facing,
      heroAction: heroAction,
      potType: potType,
      facingSizeBb: facingSizeBb,
      heroSizeBb: heroSizeBb,
      potBeforeBb: potBeforeBb,
      effStackBb: effStackBb,
      result: result,
      resultAmountBb: resultAmountBb,
      userNote: userNote,
      isTournament: isTournament,
      tournamentStage: tournamentStage,
      ante: ante,
    );

PokerHand toHand(QuickHandSynthesis s) => PokerHand(
      id: 'h',
      userId: 'u',
      playedAt: DateTime(2026, 1, 1),
      tableSetup: s.tableSetup,
      players: s.players,
      streets: s.streets,
      notes: s.notes,
      isQuickEntry: true,
    );

/// Sum of a seat's per-street max contributions across all streets, in chips.
int totalContribution(QuickHandSynthesis s, int seat) {
  var total = 0;
  for (final street in s.streets) {
    var seatMax = 0;
    for (final a in street.actions) {
      if (a.seat == seat && (a.amount ?? 0) > seatMax) seatMax = a.amount!;
    }
    total += seatMax;
  }
  return total;
}

void main() {
  group('quickHandNotation', () {
    test('classifies pairs, suited, offsuit, and normalizes rank order', () {
      expect(quickHandNotation(['As', 'Ad']), equals('AA'));
      expect(quickHandNotation(['As', 'Ks']), equals('AKs'));
      expect(quickHandNotation(['As', 'Kd']), equals('AKo'));
      expect(quickHandNotation(['Kd', 'As']), equals('AKo'));
      expect(quickHandNotation(['2c', '7d']), equals('72o'));
      expect(quickHandNotation(['Th', '9h']), equals('T9s'));
    });
  });

  group('position mapping', () {
    test('hero position label round-trips through handHeroPosition', () {
      const combos = [
        (6, 'CO'), (6, 'BTN'), (6, 'SB'), (6, 'UTG'),
        (9, 'UTG+1'), (9, 'MP'), (3, 'SB'), (2, 'BTN'),
      ];
      for (final (seats, label) in combos) {
        final hand = toHand(
            synthesizeQuickHand(makeInput(numSeats: seats, positionLabel: label)));
        expect(handHeroPosition(hand), equals(label),
            reason: '$seats-max $label');
      }
    });

    test('hero in the BB relocates the villain to the button', () {
      for (final seats in [2, 6, 9]) {
        final s = synthesizeQuickHand(
            makeInput(numSeats: seats, positionLabel: 'BB'));
        expect(handHeroPosition(toHand(s)), equals('BB'));
        final villain = s.players.firstWhere((p) => !p.isHero);
        expect(villain.seatIndex, equals(0), reason: '$seats-max');
        expect(villain.seatIndex, isNot(equals(s.tableSetup.heroSeat)));
      }
    });

    test('unknown position label throws', () {
      expect(() => synthesizeQuickHand(makeInput(positionLabel: 'XX')),
          throwsArgumentError);
    });
  });

  group('streets and board', () {
    test('streetReached matches the decision street, board or not', () {
      const cases = [
        (Street.preflop, <String>[], 'Pre-flop'),
        (Street.flop, ['2h', '7d', 'Ks'], 'Flop'),
        (Street.turn, <String>[], 'Turn'), // board unknown — still 3 streets
        (Street.turn, ['2h', '7d', 'Ks', '9c'], 'Turn'),
        (Street.river, ['2h', '7d', 'Ks', '9c', 'Ah'], 'River'),
      ];
      for (final (street, board, label) in cases) {
        final hand = toHand(synthesizeQuickHand(makeInput(
          decisionStreet: street,
          boardCards: board,
          facing: street == Street.preflop
              ? QuickFacing.openRaise
              : QuickFacing.bet,
        )));
        expect(hand.streetReached, equals(label));
        expect(hand.allCommunityCards, equals(board));
      }
    });

    test('board cards land on the right streets', () {
      final s = synthesizeQuickHand(makeInput(
        decisionStreet: Street.river,
        boardCards: ['2h', '7d', 'Ks', '9c', 'Ah'],
        facing: QuickFacing.bet,
      ));
      expect(s.streets[0].communityCards, isEmpty);
      expect(s.streets[1].communityCards, equals(['2h', '7d', 'Ks']));
      expect(s.streets[2].communityCards, equals(['9c']));
      expect(s.streets[3].communityCards, equals(['Ah']));
    });
  });

  group('preflop story (chart-informed)', () {
    test('premium hand → hero is the preflop aggressor (3-bet pot)', () {
      // AA in the CO with a 30bb turn pot: hero 3-bet, villain (opener) called.
      final s = synthesizeQuickHand(makeInput(
        heroCards: ['As', 'Ad'],
        decisionStreet: Street.turn,
        facing: QuickFacing.bet,
        heroAction: QuickHeroAction.call,
        potBeforeBb: 30,
      ));
      final preflopRaises = s.streets[0]
          .actions
          .where((a) => a.type == ActionType.raise)
          .toList();
      expect(preflopRaises, isNotEmpty);
      expect(preflopRaises.last.seat, equals(s.tableSetup.heroSeat),
          reason: 'the last preflop raiser should be Hero');
      expect(s.notes, contains('Hero 3-bet'));
    });

    test('junk hand → hero is never the synthesized preflop aggressor', () {
      // 72o in the CO: villain opens (UTG seat), hero just calls.
      final s = synthesizeQuickHand(makeInput(
        heroCards: ['7c', '2d'],
        decisionStreet: Street.turn,
        facing: QuickFacing.bet,
        heroAction: QuickHeroAction.fold,
        potBeforeBb: 12,
      ));
      final heroSeat = s.tableSetup.heroSeat;
      final preflopHeroRaises = s.streets[0]
          .actions
          .where((a) => a.seat == heroSeat && a.type == ActionType.raise);
      expect(preflopHeroRaises, isEmpty);
      expect(s.notes, contains('Villain opened, Hero called'));
      final villain = s.players.firstWhere((p) => !p.isHero);
      expect(villain.seatIndex, equals(3), reason: 'opener sits UTG');
    });

    test('junk hand first-to-act → limp-call line, villain in the BB', () {
      final s = synthesizeQuickHand(makeInput(
        heroCards: ['7c', '2d'],
        positionLabel: 'UTG',
        decisionStreet: Street.flop,
        boardCards: ['2h', '7d', 'Ks'],
        facing: QuickFacing.bet,
        heroAction: QuickHeroAction.call,
        potBeforeBb: 8,
      ));
      expect(s.notes, contains('Hero limped, Villain raised, Hero called'));
      final villain = s.players.firstWhere((p) => !p.isHero);
      expect(villain.seatIndex, equals(s.tableSetup.bbSeat));
      // Hero's limp precedes the villain's raise.
      final actions = s.streets[0].actions;
      final limpIdx = actions.indexWhere(
          (a) => a.seat == s.tableSetup.heroSeat && a.type == ActionType.call);
      final raiseIdx = actions.indexWhere((a) => a.type == ActionType.raise);
      expect(limpIdx, lessThan(raiseIdx));
    });

    test('explicit potType override is respected', () {
      final s = synthesizeQuickHand(makeInput(
        heroCards: ['As', 'Ad'],
        decisionStreet: Street.flop,
        boardCards: ['2h', '7d', 'Ks'],
        facing: QuickFacing.checkedTo,
        heroAction: QuickHeroAction.bet,
        potType: QuickPotType.fourBet,
        potBeforeBb: 44,
      ));
      expect(s.notes, contains('4-bet pot — Hero opened'));
      // Four preflop raises/calls beyond the posts.
      final raises = s.streets[0]
          .actions
          .where((a) => a.type == ActionType.raise)
          .length;
      expect(raises, equals(3)); // open, 3-bet, 4-bet
    });

    test('premium with no pot given still assumes a 3-bet pot', () {
      final s = synthesizeQuickHand(makeInput(
        heroCards: ['As', 'Ad'],
        decisionStreet: Street.flop,
        boardCards: ['2h', '7d', 'Ks'],
        facing: QuickFacing.checkedTo,
        heroAction: QuickHeroAction.bet,
      ));
      expect(s.notes, contains('3-bet pot'));
    });
  });

  group('pot reconciliation', () {
    test('stated turn pot is reflected exactly in the synthesized streets',
        () {
      // 1/2 game, 30bb entering the turn: 3-bet pot (AKo 3-bets) of 18bb +
      // a flop bet pair of 6bb each = exactly 30bb = 60 chips.
      final s = synthesizeQuickHand(makeInput(
        decisionStreet: Street.turn,
        facing: QuickFacing.bet,
        facingSizeBb: 20,
        heroAction: QuickHeroAction.call,
        potBeforeBb: 30,
      ));
      final hand = toHand(s);
      // 60 chips entering the turn + villain 40 + hero 40 on the turn.
      expect(hand.finalPot, equals(60 + 40 + 40));
    });

    test('river decision reconciles across two synthesized streets', () {
      final s = synthesizeQuickHand(makeInput(
        decisionStreet: Street.river,
        facing: QuickFacing.checkedTo,
        heroAction: QuickHeroAction.check,
        potBeforeBb: 60,
      ));
      final hand = toHand(s);
      // Decision street adds nothing (check/check) — finalPot should equal
      // the stated 60bb = 120 chips, within chip rounding.
      expect((hand.finalPot - 120).abs(), lessThanOrEqualTo(3));
    });

    test('contributions never exceed the effective stack', () {
      final s = synthesizeQuickHand(makeInput(
        decisionStreet: Street.turn,
        facing: QuickFacing.checkedTo,
        heroAction: QuickHeroAction.check,
        potBeforeBb: 100,
        effStackBb: 20,
      ));
      final stackChips = 20 * 2;
      for (final p in s.players) {
        expect(totalContribution(s, p.seatIndex),
            lessThanOrEqualTo(stackChips),
            reason: 'seat ${p.seatIndex}');
      }
    });

    test('hero call matches the facing amount (preflop decision)', () {
      final s = synthesizeQuickHand(makeInput(
        facing: QuickFacing.threeBet,
        facingSizeBb: 11,
        heroAction: QuickHeroAction.call,
      ));
      final preflop = s.streets.single.actions;
      final villainRaise =
          preflop.firstWhere((a) => a.type == ActionType.raise);
      final heroCall = preflop.firstWhere((a) => a.type == ActionType.call);
      expect(villainRaise.amount, equals(22)); // 11bb at 1/2
      expect(heroCall.amount, equals(villainRaise.amount));
    });

    test('all-in amounts account for prior contributions', () {
      // AKo CO, 40bb flop pot → 3-bet pot, 20bb matched each. All-in street
      // total = 100bb - 20bb = 80bb = 160 chips at 1/2.
      final s = synthesizeQuickHand(makeInput(
        decisionStreet: Street.flop,
        boardCards: ['2h', '7d', 'Ks'],
        facing: QuickFacing.allIn,
        heroAction: QuickHeroAction.call,
        potBeforeBb: 40,
      ));
      final allIn = s.streets[1].actions.firstWhere((a) => a.isAllIn);
      expect(allIn.amount, equals(160));
    });
  });

  group('replayer seat invariant', () {
    test('every action seat belongs to a player, across the full matrix', () {
      for (final cards in [
        ['As', 'Kd'], // chart hand
        ['7c', '2d'], // junk hand — exercises the fallback branches
      ]) {
        for (final seats in [2, 4, 6, 9]) {
          for (final label in TableSetup.positionLabels(seats)) {
            for (final street in Street.values) {
              for (final facing in QuickFacing.values) {
                for (final action in QuickHeroAction.values) {
                  final s = synthesizeQuickHand(makeInput(
                    heroCards: cards,
                    numSeats: seats,
                    positionLabel: label,
                    decisionStreet: street,
                    facing: facing,
                    heroAction: action,
                    potBeforeBb: street == Street.preflop ? null : 12,
                  ));
                  final playerSeats =
                      s.players.map((p) => p.seatIndex).toSet();
                  expect(playerSeats.length, equals(2),
                      reason: 'hero and villain must occupy distinct seats '
                          '($seats-max $label)');
                  for (final st in s.streets) {
                    for (final a in st.actions) {
                      expect(playerSeats.contains(a.seat), isTrue,
                          reason: 'action ${a.type} on seat ${a.seat} has no '
                              'player ($seats-max $label, $street, $facing, '
                              '$action, $cards)');
                    }
                  }
                }
              }
            }
          }
        }
      }
    });
  });

  group('notes', () {
    test('context block: instruction, assumptions, recorded decision', () {
      final s = synthesizeQuickHand(makeInput(
        decisionStreet: Street.turn,
        boardCards: ['2h', '7d', 'Ks', '9c'],
        facing: QuickFacing.bet,
        facingSizeBb: 20,
        heroAction: QuickHeroAction.raise,
        heroSizeBb: 55,
        potBeforeBb: 30,
        result: QuickResult.won,
        resultAmountBb: 140,
        userNote: 'Villain snap-called preflop.',
      ));
      expect(s.notes, startsWith('[Quick entry]'));
      expect(s.notes, contains('Evaluate ONLY the recorded decision'));
      expect(s.notes, contains('6-max 1/2 cash'));
      expect(s.notes, contains('Hero CO with As Kd'));
      expect(s.notes, contains('~100bb effective'));
      expect(s.notes, contains('Board: 2h 7d Ks 9c'));
      expect(s.notes, contains('Assumed (not recorded):'));
      expect(s.notes, contains('reaching ~30bb on the turn'));
      expect(
          s.notes,
          contains('RECORDED Turn decision: facing a bet of 20bb '
              'into a pot of ~30bb; Hero raised to 55bb.'));
      expect(s.notes, contains('Result: won ~140bb.'));
      expect(s.notes, endsWith('Villain snap-called preflop.'));
    });

    test('preflop decision carries no assumption line', () {
      final s = synthesizeQuickHand(makeInput());
      expect(s.notes, isNot(contains('Assumed (not recorded)')));
      expect(s.notes, isNot(contains('Board:')));
      expect(s.notes, isNot(contains('Result:')));
      expect(s.notes, isNot(contains('\n\n')));
      expect(s.notes,
          contains('RECORDED Pre-flop decision: facing an open to 2.5bb'));
      expect(s.notes, contains('Hero called'));
    });
  });

  group('tournament passthrough', () {
    test('ante lands in the table setup and notes say tournament', () {
      final s = synthesizeQuickHand(makeInput(
        smallBlind: 100,
        bigBlind: 200,
        isTournament: true,
        tournamentStage: 'final_table',
        ante: 25,
      ));
      expect(s.tableSetup.ante, equals(25));
      expect(s.notes, contains('100/200 tournament (final_table)'));
    });

    test('cash hands never carry an ante', () {
      final s = synthesizeQuickHand(makeInput(ante: 25));
      expect(s.tableSetup.ante, isNull);
    });
  });
}
