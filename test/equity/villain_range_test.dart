import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';
import 'package:tablelab/models/player_read.dart';

// 6-max seats with buttonSeat 0: 0=BTN, 1=SB, 2=BB, 3=UTG, 4=HJ, 5=CO.

PokerHand _hand({
  required int heroSeat,
  required List<String> heroCards,
  required List<StreetData> streets,
  List<HandPlayer> extraPlayers = const [],
  int villainSeat = 0,
  List<String>? villainCards,
  String villainName = 'Villain',
  bool isTournament = false,
  bool isQuickEntry = false,
  int? straddle,
}) {
  return PokerHand(
    id: 'h1',
    userId: 'u1',
    playedAt: DateTime(2026, 6, 1),
    tableSetup: TableSetup(
      numSeats: 6,
      buttonSeat: 0,
      heroSeat: heroSeat,
      smallBlind: 1,
      bigBlind: 2,
      straddle: straddle,
    ),
    players: [
      HandPlayer(
        seatIndex: heroSeat,
        name: 'Hero',
        startingStack: 200,
        isHero: true,
        holeCards: heroCards,
      ),
      HandPlayer(
        seatIndex: villainSeat,
        name: villainName,
        startingStack: 200,
        holeCards: villainCards,
      ),
      ...extraPlayers,
    ],
    streets: streets,
    isTournament: isTournament,
    isQuickEntry: isQuickEntry,
  );
}

/// Preflop where the villain (BTN, seat 0) opens and hero (BB, seat 2) calls.
StreetData _btnOpenBbCall() => const StreetData(
      street: Street.preflop,
      actions: [
        HandAction(seat: 2, type: ActionType.post, amount: 2),
        HandAction(seat: 0, type: ActionType.raise, amount: 5),
        HandAction(seat: 2, type: ActionType.call, amount: 5),
      ],
    );

PlayerRead _read(String label, List<String> tags) => PlayerRead(
      id: 'r1',
      userId: 'u1',
      playerLabel: label,
      tags: tags,
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
    );

int _trailPct(HandEquityCheck check) {
  final note = check.villains.first.rangeTrail.first;
  final m = RegExp(r'~(\d+)% of hands').firstMatch(note);
  expect(m, isNotNull, reason: 'no percentage in trail note: $note');
  return int.parse(m!.group(1)!);
}

void main() {
  group('chenScore + ranking', () {
    test('orders premium hands correctly', () {
      expect(chenScore('AA'), 20);
      expect(chenScore('AA') > chenScore('KK'), isTrue);
      expect(chenScore('KK') > chenScore('QQ'), isTrue);
      expect(chenScore('AKs') > chenScore('AKo'), isTrue);
      expect(chenScore('AKo') > chenScore('72o'), isTrue);
    });

    test('ranking covers all 169 hands, strongest first', () {
      expect(kRankedHands.length, 169);
      expect(kRankedHands.toSet().length, 169);
      expect(kRankedHands.first, 'AA');
      final aa = kRankedHands.indexOf('AA');
      final kk = kRankedHands.indexOf('KK');
      final j7o = kRankedHands.indexOf('J7o');
      expect(aa < kk, isTrue);
      expect(kk < j7o, isTrue);
    });
  });

  group('adjustRangeSize', () {
    const base = {'AA', 'KK', 'QQ', 'AKs', 'AKo', 'AQs', 'KQs', 'JTs'};

    test('factor 1 returns the range unchanged', () {
      expect(adjustRangeSize(base, 1.0), base);
    });

    test('widening produces a superset with more combos', () {
      final widened = adjustRangeSize(base, 2.0);
      expect(widened.containsAll(base), isTrue);
      expect(widened.length, greaterThan(base.length));
    });

    test('tightening keeps the strongest hands', () {
      final tightened = adjustRangeSize(base, 0.4);
      expect(tightened.length, lessThan(base.length));
      expect(tightened.contains('AA'), isTrue);
      expect(base.containsAll(tightened), isTrue);
    });
  });

  group('preflop chart selection (via range trail)', () {
    test('villain open-raise uses their position opening range', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
        ]),
        iterations: 2000,
      );
      expect(check, isNotNull);
      expect(check!.villains.first.rangeTrail.first,
          contains('BTN opening range'));
    });

    test('villain BB defend vs a middle-position open uses the call chart',
        () async {
      // Hero opens from CO (seat 5), villain BB (seat 2) calls.
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 5,
          heroCards: ['As', 'Kh'],
          villainSeat: 2,
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 5, type: ActionType.raise, amount: 5),
              HandAction(seat: 2, type: ActionType.call, amount: 5),
            ]),
          ],
        ),
        iterations: 2000,
      );
      expect(check, isNotNull);
      final note = check!.villains.first.rangeTrail.first;
      expect(note, contains('called a middle-position open'));
      expect(note, contains('BB defending range'));
    });

    test('villain 3-bet uses a 3-bet range', () async {
      // Hero opens BTN (seat 0), villain BB (seat 2) 3-bets, hero calls.
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 0,
          heroCards: ['As', 'Kh'],
          villainSeat: 2,
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 0, type: ActionType.raise, amount: 5),
              HandAction(seat: 2, type: ActionType.raise, amount: 18),
              HandAction(seat: 0, type: ActionType.call, amount: 18),
            ]),
          ],
        ),
        iterations: 2000,
      );
      expect(check, isNotNull);
      expect(check!.villains.first.rangeTrail.first, contains('3-bet range'));
    });
  });

  group('reads tag adjustments', () {
    Future<int> pctWithTags(List<String> tags) async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
        ]),
        reads: tags.isEmpty ? const [] : [_read('Villain', tags)],
        iterations: 2000,
      );
      return _trailPct(check!);
    }

    test('LAG widens, Nit tightens, relative to the untagged chart',
        () async {
      final base = await pctWithTags([]);
      final lag = await pctWithTags(['lag_player']);
      final nit = await pctWithTags(['nit']);
      expect(lag, greaterThan(base));
      expect(nit, lessThan(base));
    });

    test('widened trail says so', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
        ]),
        reads: [_read('Villain', ['maniac'])],
        iterations: 2000,
      );
      expect(check!.villains.first.rangeTrail.first, contains('widened'));
    });
  });

  group('postflop narrowing', () {
    StreetData flopWithVillainAction(HandAction villainAction) => StreetData(
          street: Street.flop,
          communityCards: const ['Kh', '7d', '2c'],
          actions: [
            const HandAction(seat: 2, type: ActionType.check),
            villainAction,
            const HandAction(seat: 2, type: ActionType.call, amount: 6),
          ],
        );

    test('a bet narrows the range; the trail records the kept fraction',
        () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
          flopWithVillainAction(const HandAction(
              seat: 0,
              type: ActionType.raise,
              amount: 6,
              isOpeningBet: true)),
        ]),
        iterations: 2000,
      );
      expect(check, isNotNull);
      final trail = check!.villains.first.rangeTrail;
      expect(trail.any((n) => n.startsWith('Flop: bet → kept top 55%')),
          isTrue,
          reason: 'trail was: $trail');
    });

    test('a raise narrows more than a bet', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
          StreetData(
            street: Street.flop,
            communityCards: const ['Kh', '7d', '2c'],
            actions: const [
              HandAction(
                  seat: 2,
                  type: ActionType.raise,
                  amount: 6,
                  isOpeningBet: true),
              HandAction(seat: 0, type: ActionType.raise, amount: 20),
              HandAction(seat: 2, type: ActionType.call, amount: 20),
            ],
          ),
        ]),
        iterations: 2000,
      );
      final trail = check!.villains.first.rangeTrail;
      expect(trail.any((n) => n.startsWith('Flop: raise → kept top 30%')),
          isTrue,
          reason: 'trail was: $trail');
    });

    test('a check leaves the range unchanged', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
          const StreetData(
            street: Street.flop,
            communityCards: ['Kh', '7d', '2c'],
            actions: [
              HandAction(seat: 2, type: ActionType.check),
              HandAction(seat: 0, type: ActionType.check),
            ],
          ),
        ]),
        iterations: 2000,
      );
      final trail = check!.villains.first.rangeTrail;
      expect(trail.any((n) => n.contains('kept top')), isFalse,
          reason: 'trail was: $trail');
    });
  });

  group('per-street equity', () {
    test('AA has strong preflop equity vs an opening range', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
        ]),
        iterations: 5000,
      );
      expect(check!.streets, hasLength(1));
      expect(check.streets.first.street, Street.preflop);
      expect(check.streets.first.heroEquity, greaterThan(0.75));
    });

    test('one result per street reached', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
          const StreetData(
            street: Street.flop,
            communityCards: ['Kh', '7d', '2c'],
            actions: [
              HandAction(seat: 2, type: ActionType.check),
              HandAction(seat: 0, type: ActionType.check),
            ],
          ),
          const StreetData(
            street: Street.turn,
            communityCards: ['3s'],
            actions: [
              HandAction(seat: 2, type: ActionType.check),
              HandAction(seat: 0, type: ActionType.check),
            ],
          ),
        ]),
        iterations: 2000,
      );
      expect(check!.streets.map((s) => s.street).toList(),
          [Street.preflop, Street.flop, Street.turn]);
      expect(check.streets.last.boardSoFar, ['Kh', '7d', '2c', '3s']);
    });

    test('exact villain hole cards beat any range assumption', () async {
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 2,
          heroCards: ['As', 'Ah'],
          villainCards: ['7c', '2d'],
          streets: [_btnOpenBbCall()],
        ),
        iterations: 5000,
      );
      expect(check!.villains.first.usedExactCards, isTrue);
      expect(check.streets.first.heroEquity, greaterThan(0.85));
    });
  });

  group('player filtering', () {
    test('a villain who only folded preflop is excluded', () async {
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 2,
          heroCards: ['As', 'Ah'],
          extraPlayers: const [
            HandPlayer(seatIndex: 3, name: 'Folder', startingStack: 200),
          ],
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 3, type: ActionType.fold),
              HandAction(seat: 0, type: ActionType.raise, amount: 5),
              HandAction(seat: 2, type: ActionType.call, amount: 5),
            ]),
          ],
        ),
        iterations: 2000,
      );
      expect(check!.streets.first.villainCount, 1);
      expect(check.villains.map((v) => v.name), isNot(contains('Folder')));
    });

    test('a villain folding on the flop drops out of the turn count',
        () async {
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 2,
          heroCards: ['As', 'Ah'],
          extraPlayers: const [
            HandPlayer(seatIndex: 5, name: 'Caller', startingStack: 200),
          ],
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 0, type: ActionType.raise, amount: 5),
              HandAction(seat: 5, type: ActionType.call, amount: 5),
              HandAction(seat: 2, type: ActionType.call, amount: 5),
            ]),
            const StreetData(
              street: Street.flop,
              communityCards: ['Kh', '7d', '2c'],
              actions: [
                HandAction(seat: 2, type: ActionType.check),
                HandAction(
                    seat: 0,
                    type: ActionType.raise,
                    amount: 10,
                    isOpeningBet: true),
                HandAction(seat: 5, type: ActionType.fold),
                HandAction(seat: 2, type: ActionType.call, amount: 10),
              ],
            ),
            const StreetData(
              street: Street.turn,
              communityCards: ['3s'],
              actions: [
                HandAction(seat: 2, type: ActionType.check),
                HandAction(seat: 0, type: ActionType.check),
              ],
            ),
          ],
        ),
        iterations: 2000,
      );
      final byStreet = {
        for (final s in check!.streets) s.street: s.villainCount,
      };
      expect(byStreet[Street.preflop], 2);
      expect(byStreet[Street.flop], 2); // folds during the flop
      expect(byStreet[Street.turn], 1);
    });
  });

  group('straddle handling', () {
    // 6-max, button seat 0 → seat 3 is the UTG seat, which is the straddle
    // seat when a straddle is on (positionName returns 'STR').

    test('a straddler defending vs a late open gets a wide BB-style range, '
        'not an IP cold-call range', () async {
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 0, // hero BTN opens
          heroCards: ['As', 'Kh'],
          villainSeat: 3, // villain is the straddler
          straddle: 4,
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 3, type: ActionType.postStraddle, amount: 4),
              HandAction(seat: 0, type: ActionType.raise, amount: 12),
              HandAction(seat: 3, type: ActionType.call, amount: 12),
            ]),
          ],
        ),
        iterations: 2000,
      );
      expect(check, isNotNull);
      final note = check!.villains.first.rangeTrail.first;
      expect(note, contains('STR defending range'));
      expect(note, contains('straddle treated as a blind'));
      // The old bug assigned the ~10% IP cold-call chart here.
      expect(_trailPct(check), greaterThan(20));
    });

    test('the first raise after a straddle is still an open', () async {
      // Hero straddles, villain BTN raises — the straddle post must not
      // count as a raise level, so the villain reads as the opener.
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 3,
          heroCards: ['As', 'Kh'],
          villainSeat: 0,
          straddle: 4,
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 3, type: ActionType.postStraddle, amount: 4),
              HandAction(seat: 0, type: ActionType.raise, amount: 12),
              HandAction(seat: 3, type: ActionType.call, amount: 12),
            ]),
          ],
        ),
        iterations: 2000,
      );
      expect(check!.villains.first.rangeTrail.first,
          contains('BTN opening range'));
    });

    test('a straddler 3-betting uses a blind 3-bet range', () async {
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 0,
          heroCards: ['As', 'Kh'],
          villainSeat: 3,
          straddle: 4,
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 3, type: ActionType.postStraddle, amount: 4),
              HandAction(seat: 0, type: ActionType.raise, amount: 12),
              HandAction(seat: 3, type: ActionType.raise, amount: 40),
              HandAction(seat: 0, type: ActionType.call, amount: 40),
            ]),
          ],
        ),
        iterations: 2000,
      );
      final note = check!.villains.first.rangeTrail.first;
      expect(note, contains('3-bet range'));
      // 3-bets are not straddle-widened — only passive defends are.
      expect(note, isNot(contains('straddle treated as a blind')));
    });
  });

  group('edge cases', () {
    test('returns null without hero hole cards', () async {
      final hand = PokerHand(
        id: 'h1',
        userId: 'u1',
        playedAt: DateTime(2026, 6, 1),
        tableSetup: const TableSetup(
            numSeats: 6,
            buttonSeat: 0,
            heroSeat: 2,
            smallBlind: 1,
            bigBlind: 2),
        players: const [
          HandPlayer(
              seatIndex: 2, name: 'Hero', startingStack: 200, isHero: true),
          HandPlayer(seatIndex: 0, name: 'Villain', startingStack: 200),
        ],
        streets: [_btnOpenBbCall()],
      );
      expect(await computeHandEquityCheck(hand, iterations: 500), isNull);
    });

    test('quick-entry hands are flagged as synthesized', () async {
      final check = await computeHandEquityCheck(
        _hand(
            heroSeat: 2,
            heroCards: ['As', 'Ah'],
            isQuickEntry: true,
            streets: [_btnOpenBbCall()]),
        iterations: 500,
      );
      expect(check!.basedOnSynthesizedAction, isTrue);
    });
  });
}
