import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/decision_context.dart';
import 'package:tablelab/equity/gto_frequency_library.dart';
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
  int stack = 200,
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
        startingStack: stack,
        isHero: true,
        holeCards: heroCards,
      ),
      HandPlayer(
        seatIndex: villainSeat,
        name: villainName,
        startingStack: stack,
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

    test('a wizard-style all-in (raise + isAllIn) classifies as all-in, '
        'not bet', () async {
      // The full Hand wizard records all-ins as ActionType.raise/call with
      // isAllIn:true — never ActionType.allIn. The engine must still narrow
      // to the tightest all-in keep, not the wider bet/raise keep.
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
          flopWithVillainAction(const HandAction(
              seat: 0,
              type: ActionType.raise,
              amount: 200,
              isOpeningBet: true,
              isAllIn: true)),
        ]),
        iterations: 2000,
      );
      final trail = check!.villains.first.rangeTrail;
      expect(
          trail.any((n) =>
              n.startsWith('Flop: all-in') &&
              n.contains('polarized: top 18% value')),
          isTrue,
          reason: 'trail was: $trail');
    });

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
      expect(
          trail.any((n) =>
              n.startsWith('Flop: bet') &&
              n.contains('polarized: top 30% value')),
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
      expect(
          trail.any((n) =>
              n.startsWith('Flop: raise') &&
              n.contains('polarized: top 22% value')),
          isTrue,
          reason: 'trail was: $trail');
    });

    test('a small (blocker) bet is modeled as merged, not polarized', () async {
      // River bet of 6 into a 70 pot (~9%) — a small/blocker sizing. The trail
      // must read "merged, NOT polarized", never "polarized" (the reported bug:
      // a tiny ~11%-pot river bet was labeled polarized).
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 0, streets: [
          _btnOpenBbCall(), // pot 10
          const StreetData(
            street: Street.flop,
            communityCards: ['Kh', '7d', '2c'],
            actions: [
              HandAction(seat: 2, type: ActionType.check),
              HandAction(
                  seat: 0,
                  type: ActionType.raise,
                  amount: 30,
                  isOpeningBet: true),
              HandAction(seat: 2, type: ActionType.call, amount: 30),
            ], // +60 → pot 70
          ),
          const StreetData(
            street: Street.turn,
            communityCards: ['3s'],
            actions: [
              HandAction(seat: 2, type: ActionType.check),
              HandAction(seat: 0, type: ActionType.check),
            ],
          ),
          const StreetData(
            street: Street.river,
            communityCards: ['9h'],
            actions: [
              HandAction(seat: 2, type: ActionType.check),
              HandAction(
                  seat: 0,
                  type: ActionType.raise,
                  amount: 6,
                  isOpeningBet: true), // 6 into 70 ≈ 9% pot
              HandAction(seat: 2, type: ActionType.call, amount: 6),
            ],
          ),
        ]),
        iterations: 2000,
      );
      final trail = check!.villains.first.rangeTrail;
      expect(
          trail.any((n) =>
              n.startsWith('River:') && n.contains('merged, NOT polarized')),
          isTrue,
          reason: 'trail was: $trail');
      expect(
          trail.any((n) => n.startsWith('River:') && n.contains('→ polarized:')),
          isFalse,
          reason: 'small bet must not be labeled polarized; trail was: $trail');
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

    test('a bluff-catcher keeps realistic equity vs a polarized betting line '
        '(not ~0)', () async {
      // Regression (JdTd hand): the old value-only narrowing collapsed any
      // bluff-catcher to ~0% because it kept only the strongest made hands.
      // Hero flops/rivers top pair while villain bets every street; a polarized
      // betting range still contains busted draws hero beats, so river equity
      // must be well above zero. A nit (who barely bluffs) must score lower.
      StreetData betStreet(Street s, List<String> cards) => StreetData(
            street: s,
            communityCards: cards,
            actions: [
              const HandAction(seat: 2, type: ActionType.check),
              const HandAction(
                  seat: 0,
                  type: ActionType.raise,
                  amount: 20,
                  isOpeningBet: true),
              const HandAction(seat: 2, type: ActionType.call, amount: 20),
            ],
          );
      Future<double> riverEq(List<String> tags) async {
        final check = await computeHandEquityCheck(
          _hand(
            heroSeat: 2,
            heroCards: ['Jd', 'Td'],
            villainSeat: 0,
            streets: [
              _btnOpenBbCall(),
              betStreet(Street.flop, ['Js', '4d', '5c']),
              betStreet(Street.turn, ['9c']),
              betStreet(Street.river, ['2h']),
            ],
          ),
          reads: tags.isEmpty ? const [] : [_read('Villain', tags)],
          iterations: 8000,
        );
        return check!.streets
            .firstWhere((s) => s.street == Street.river)
            .heroEquity;
      }

      final noRead = await riverEq([]);
      expect(noRead, greaterThan(0.12),
          reason: 'top pair must beat villain bluffs, not collapse to ~0 '
              '(was $noRead)');
      final nit = await riverEq(['nit']);
      expect(nit, lessThan(noRead),
          reason: 'a nit bluffs less, so the bluff-catcher is worth less vs '
              'them (nit=$nit, noRead=$noRead)');
    });

    test('recorded showdown cards do NOT collapse equity to the result '
        '(villain modeled by range for result-independence)', () async {
      // Villain turned over 7c2d at showdown, but coaching equity must be hero
      // vs villain's RANGE at decision time — never hero vs the one hand they
      // later showed (that injects the outcome into the decision analysis).
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 2,
          heroCards: ['As', 'Ah'],
          villainCards: ['7c', '2d'],
          streets: [_btnOpenBbCall()],
        ),
        iterations: 5000,
      );
      expect(check!.villains.first.usedExactCards, isFalse);
      // The range was modeled (trail names a chart + % of hands), not the exact
      // hand.
      expect(check.villains.first.rangeTrail.first, contains('% of hands'));
      expect(check.streets.first.heroEquity, greaterThan(0.75));
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

  group('equityCheckFacts', () {
    test('renders a per-street equity FACT plus a villain-range FACT', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
        ]),
        iterations: 3000,
      );
      final facts = equityCheckFacts(check!);
      expect(facts, isNotEmpty);
      expect(facts.first, contains('Hero equity'));
      expect(facts.first, contains('Monte Carlo'));
      expect(facts.first, contains('pre-flop ~'));
      expect(facts.first, contains('MUST be consistent'));
      expect(facts.any((f) => f.contains('range behind the equity')), isTrue);
    });

    test('emits the realized-equity HEURISTIC line when EQR fields are set', () {
      // Exercises the LIVE wording (the prod copy), not a dead helper.
      final check = HandEquityCheck(
        streets: const [
          StreetEquityCheck(
            street: Street.flop,
            heroEquity: 0.50,
            boardSoFar: ['Ks', '7c', '2d'],
            villainCount: 1,
            iterations: 1000,
            realizedEquity: 0.375, // 0.50 × 0.75 (marginal made, OOP)
            realizedHandClass: HandClass.marginalMade,
            heroInPosition: false,
          ),
        ],
        villains: [],
        basedOnSynthesizedAction: false,
      );
      final realized = equityCheckFacts(check)
          .firstWhere((f) => f.contains('Equity REALIZATION'));
      expect(realized, startsWith('[HEURISTIC —'));
      expect(realized, contains('~50%')); // raw
      expect(realized, contains('realized ~38%')); // 0.375 → 38
      expect(realized, contains('OOP'));
      expect(realized.toLowerCase(), contains('take precedence'));
    });

    test('flags synthesized (Quick Hand) action in the caveat', () async {
      final check = await computeHandEquityCheck(
        _hand(
            heroSeat: 2,
            heroCards: ['As', 'Ah'],
            isQuickEntry: true,
            streets: [_btnOpenBbCall()]),
        iterations: 2000,
      );
      expect(equityCheckFacts(check!).first, contains('Quick Hand'));
    });

    test('AA folding to a nit shove yields a low river equity', () async {
      // The device-review hand: AA on Tc7d4c3hKc vs a nit who shoves the
      // river. The injected FACT must report a low river equity so the model
      // can't claim showdown value.
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 0,
          heroCards: ['Ah', 'Ad'],
          villainSeat: 2,
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 0, type: ActionType.raise, amount: 5),
              HandAction(seat: 2, type: ActionType.call, amount: 5),
            ]),
            const StreetData(
              street: Street.flop,
              communityCards: ['Tc', '7d', '4c'],
              actions: [
                HandAction(seat: 2, type: ActionType.check),
                HandAction(
                    seat: 0,
                    type: ActionType.raise,
                    amount: 7,
                    isOpeningBet: true),
                HandAction(seat: 2, type: ActionType.call, amount: 7),
              ],
            ),
            const StreetData(
              street: Street.turn,
              communityCards: ['3h'],
              actions: [
                HandAction(seat: 2, type: ActionType.check),
                HandAction(
                    seat: 0,
                    type: ActionType.raise,
                    amount: 28,
                    isOpeningBet: true),
                HandAction(seat: 2, type: ActionType.call, amount: 28),
              ],
            ),
            const StreetData(
              street: Street.river,
              communityCards: ['Kc'],
              actions: [
                HandAction(
                    seat: 2,
                    type: ActionType.allIn,
                    amount: 92,
                    isAllIn: true),
                HandAction(seat: 0, type: ActionType.fold),
              ],
            ),
          ],
        ),
        reads: [_read('Villain', ['nit'])],
        iterations: 8000,
      );
      final river = check!.streets.firstWhere((s) => s.street == Street.river);
      expect(river.heroEquity, lessThan(0.35),
          reason: "AA should beat little of a nit's river shove range");
    });
  });

  group('SPR & commitment (DCE Tier A)', () {
    // _btnOpenBbCall: hero(BB) & villain(BTN) each commit 5 preflop → pot 10,
    // 195 behind each. A checked flop → heads-up SPR = 195/10 = 19.5.
    StreetData checkedFlop() => const StreetData(
          street: Street.flop,
          communityCards: ['Kh', '7d', '2c'],
          actions: [
            HandAction(seat: 2, type: ActionType.check),
            HandAction(seat: 0, type: ActionType.check),
          ],
        );

    test('SPR is null pre-flop', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [_btnOpenBbCall()]),
        iterations: 2000,
      );
      expect(check!.streets.first.street, Street.preflop);
      expect(check.streets.first.spr, isNull);
    });

    test('heads-up: SPR fields are set and the FACT names SPR + stack-off %',
        () async {
      // One computeHandEquityCheck call (the MC sim is the heavy cost) backs
      // both the struct-field and the FACT-string assertions.
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], streets: [
          _btnOpenBbCall(),
          checkedFlop(),
        ]),
        iterations: 2000,
      );
      final flop = check!.streets.firstWhere((s) => s.street == Street.flop);
      expect(flop.spr, closeTo(19.5, 0.1)); // 195 behind ÷ 10 pot
      expect(flop.sprIsHeadsUp, isTrue);
      expect(flop.reqStackOffEquity, closeTo(0.4875, 0.01)); // 19.5/(1+39)

      final fact = equityCheckFacts(check)
          .firstWhere((f) => f.contains('SPR & COMMITMENT'));
      expect(fact, startsWith('[HEURISTIC —'));
      expect(fact, contains('flop SPR ~19.5'));
      expect(fact, contains('needs ~49% equity'));
      expect(fact.toLowerCase(), contains('take precedence'));
    });

    test('multiway effective stack uses the SHORTEST villain, not the deepest',
        () async {
      // Hero(BB,195 behind) + deep villain(BTN,195) + short villain(CO,35) to a
      // checked flop, pot 15. Effective stack must be min(hero, shortest=35) →
      // SPR ~2.3, NOT min(hero, deepest=195) → SPR ~13. Guards the review fix.
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 2,
          heroCards: ['As', 'Ah'],
          extraPlayers: const [
            HandPlayer(seatIndex: 5, name: 'Shorty', startingStack: 40),
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
                HandAction(seat: 0, type: ActionType.check),
                HandAction(seat: 5, type: ActionType.check),
              ],
            ),
          ],
        ),
        iterations: 2000,
      );
      final flop = check!.streets.firstWhere((s) => s.street == Street.flop);
      expect(flop.spr, closeTo(2.33, 0.2)); // 35 (shortest) ÷ 15, not 195 ÷ 15
      expect(flop.sprIsHeadsUp, isFalse);
    });

    test('multiway: stack-off % is suppressed, FACT says multiway', () async {
      // Hero(BB) + two callers reach a checked flop → active.length == 2.
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
                HandAction(seat: 0, type: ActionType.check),
                HandAction(seat: 5, type: ActionType.check),
              ],
            ),
          ],
        ),
        iterations: 2000,
      );
      final flop = check!.streets.firstWhere((s) => s.street == Street.flop);
      expect(flop.spr, isNotNull);
      expect(flop.sprIsHeadsUp, isFalse);
      expect(flop.reqStackOffEquity, isNull);
      final fact = equityCheckFacts(check)
          .firstWhere((f) => f.contains('SPR & COMMITMENT'));
      expect(fact, contains('multiway'));
      expect(fact, isNot(contains('needs ~')));
    });

    test('SPR shrinks as the pot grows across streets', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 0, streets: [
          _btnOpenBbCall(), // pot 10
          const StreetData(
            street: Street.flop,
            communityCards: ['Kh', '7d', '2c'],
            actions: [
              HandAction(seat: 2, type: ActionType.check),
              HandAction(
                  seat: 0,
                  type: ActionType.raise,
                  amount: 30,
                  isOpeningBet: true),
              HandAction(seat: 2, type: ActionType.call, amount: 30),
            ], // +60 → pot 70
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
      final flop = check!.streets.firstWhere((s) => s.street == Street.flop);
      final turn = check.streets.firstWhere((s) => s.street == Street.turn);
      expect(flop.spr! > turn.spr!, isTrue,
          reason: 'flop SPR ${flop.spr} should exceed turn SPR ${turn.spr}');
      // Turn: 165 behind ÷ 70 pot ≈ 2.36.
      expect(turn.spr, closeTo(2.36, 0.1));
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

  group('GTO frequency library key derivation (DCE Q1)', () {
    StreetData mkFlop(List<HandAction> actions) => StreetData(
        street: Street.flop, communityCards: const ['Ks', '9h', '4c'], actions: actions);

    test('SRP BTN-open vs BB-call HU → srp_late_v_bb; OOP check-call = facing_bet',
        () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 0, streets: [
          _btnOpenBbCall(),
          mkFlop(const [
            HandAction(seat: 2, type: ActionType.check),
            HandAction(seat: 0, type: ActionType.raise, amount: 6),
            HandAction(seat: 2, type: ActionType.call, amount: 6),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, 'srp_late_v_bb');
      final flop = check.streets.firstWhere((s) => s.street == Street.flop);
      expect(flop.heroFacing, startsWith('facing_bet'));
      expect(flop.betHeroFaced, 6);
    });

    test('SB opener (out of position) → scenarioKey null', () async {
      // SB opens, BB calls — heads-up single-raised, but the SB opens OOP so the
      // library's BTN-opener cells don't apply.
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 1, heroCards: ['As', 'Ah'], villainSeat: 2, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 1, type: ActionType.post, amount: 1), // SB
            HandAction(seat: 2, type: ActionType.post, amount: 2), // BB
            HandAction(seat: 1, type: ActionType.raise, amount: 5), // SB opens
            HandAction(seat: 2, type: ActionType.call, amount: 5),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, isNull);
    });

    test('hero IP c-bet after villain check → facing_check', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 0, heroCards: ['As', 'Ah'], villainSeat: 2, streets: [
          _btnOpenBbCall(), // hero (seat 0/BTN) opens, villain (seat 2/BB) calls
          mkFlop(const [
            HandAction(seat: 2, type: ActionType.check),
            HandAction(seat: 0, type: ActionType.raise, amount: 4),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, 'srp_late_v_bb');
      final flop = check.streets.firstWhere((s) => s.street == Street.flop);
      expect(flop.heroFacing, 'facing_check');
      expect(flop.betHeroFaced, isNull);
    });

    test('hero OOP lead → first_to_act', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 0, streets: [
          _btnOpenBbCall(),
          mkFlop(const [
            HandAction(seat: 2, type: ActionType.raise, amount: 4),
            HandAction(seat: 0, type: ActionType.call, amount: 4),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      final flop = check!.streets.firstWhere((s) => s.street == Street.flop);
      expect(flop.heroFacing, 'first_to_act');
    });

    test('3-bet pot (BTN open, BB 3-bet, BTN call) → 3bp_bb_v_btn', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 0, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 2, type: ActionType.post, amount: 2),
            HandAction(seat: 0, type: ActionType.raise, amount: 5),
            HandAction(seat: 2, type: ActionType.raise, amount: 18),
            HandAction(seat: 0, type: ActionType.call, amount: 18),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, '3bp_bb_v_btn');
    });

    test('3bp maps from the CALLER side too (hero = BTN)', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 0, heroCards: ['As', 'Ah'], villainSeat: 2, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 2, type: ActionType.post, amount: 2),
            HandAction(seat: 0, type: ActionType.raise, amount: 5),
            HandAction(seat: 2, type: ActionType.raise, amount: 18),
            HandAction(seat: 0, type: ActionType.call, amount: 18),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, '3bp_bb_v_btn');
    });

    test('4-bet pot → scenarioKey null', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 0, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 2, type: ActionType.post, amount: 2),
            HandAction(seat: 0, type: ActionType.raise, amount: 5),
            HandAction(seat: 2, type: ActionType.raise, amount: 18),
            HandAction(seat: 0, type: ActionType.raise, amount: 44),
            HandAction(seat: 2, type: ActionType.call, amount: 44),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, isNull);
    });

    test('SB 3-bettor (not the BB) → scenarioKey null', () async {
      // BTN opens, SB 3-bets, BTN calls — a 3-bet pot, but the 3-bettor is the
      // SB: different range AND the solved BB-OOP orientation doesn't hold.
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 1, heroCards: ['As', 'Ah'], villainSeat: 0, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 1, type: ActionType.post, amount: 1),
            HandAction(seat: 2, type: ActionType.post, amount: 2),
            HandAction(seat: 0, type: ActionType.raise, amount: 5),
            HandAction(seat: 1, type: ActionType.raise, amount: 18),
            HandAction(seat: 0, type: ActionType.call, amount: 18),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, isNull);
    });

    test('middle-bucket opener (CO) → srp_middle_v_bb', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 5, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 2, type: ActionType.post, amount: 2),
            HandAction(seat: 5, type: ActionType.raise, amount: 5),
            HandAction(seat: 2, type: ActionType.call, amount: 5),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, 'srp_middle_v_bb');
    });

    test('early-bucket opener (UTG) → srp_early_v_bb', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 3, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 2, type: ActionType.post, amount: 2),
            HandAction(seat: 3, type: ActionType.raise, amount: 5),
            HandAction(seat: 2, type: ActionType.call, amount: 5),
          ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, 'srp_early_v_bb');
    });

    test('multiway (two villains to the flop) → scenarioKey null', () async {
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 2,
          heroCards: ['As', 'Ah'],
          villainSeat: 0,
          extraPlayers: const [
            HandPlayer(seatIndex: 5, name: 'V2', startingStack: 200),
          ],
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 5, type: ActionType.raise, amount: 5),
              HandAction(seat: 0, type: ActionType.call, amount: 5),
              HandAction(seat: 2, type: ActionType.call, amount: 5),
            ]),
          ],
        ),
        iterations: 500,
        seed: 1,
      );
      expect(check!.scenarioKey, isNull);
    });
  });

  group('GTO frequency + multiway tendency FACTs (DCE Q1)', () {
    final lib = GtoFrequencyLibrary.fromJsonString(
        File('assets/gto_freq_library.json').readAsStringSync());

    test('heads-up scenario hand (shallow SPR) emits a GTO frequency FACT',
        () async {
      final check = await computeHandEquityCheck(
        // 30bb stacks → flop SPR ~2.5 (shallow); Ks9h4c is covered at shallow.
        _hand(heroSeat: 0, heroCards: ['As', 'Ah'], villainSeat: 2, stack: 30,
            streets: [
              _btnOpenBbCall(), // hero BTN opens, villain BB calls
              const StreetData(
                  street: Street.flop,
                  communityCards: ['Ks', '9h', '4c'],
                  actions: [
                    HandAction(seat: 2, type: ActionType.check),
                    HandAction(seat: 0, type: ActionType.raise, amount: 4),
                  ]),
            ]),
        iterations: 500,
        seed: 1,
      );
      final facts = equityCheckFacts(check!, library: lib);
      final gto = facts.where((f) => f.contains('GTO frequency (')).toList();
      expect(gto, hasLength(1));
      expect(gto.first, contains('after a check to hero')); // IP c-bet node
      expect(gto.first, contains('%'));
    });

    test('deep-stacked cash spot (deep SPR) emits a GTO frequency FACT '
        '(deep covered 2026-06-30)', () async {
      final check = await computeHandEquityCheck(
        // 200bb stacks → flop SPR ~19 (deep). The library now covers the deep
        // regime (deep-cash SPR 15 ≈ 100bb; 'deep' bucket = SPR>6), so the
        // lookup hits and a GTO frequency FACT IS emitted — this was deferred
        // (no deep cells) before the 2026-06-30 deep-SPR solve.
        _hand(heroSeat: 0, heroCards: ['As', 'Ah'], villainSeat: 2, stack: 200,
            streets: [
              _btnOpenBbCall(),
              const StreetData(
                  street: Street.flop,
                  communityCards: ['Ks', '9h', '4c'],
                  actions: [
                    HandAction(seat: 2, type: ActionType.check),
                    HandAction(seat: 0, type: ActionType.raise, amount: 4),
                  ]),
            ]),
        iterations: 500,
        seed: 1,
      );
      expect(equityCheckFacts(check!, library: lib)
          .any((f) => f.contains('GTO frequency (')), isTrue);
    });

    test('no library passed → no GTO frequency FACT', () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 0, heroCards: ['As', 'Ah'], villainSeat: 2, streets: [
          _btnOpenBbCall(),
          const StreetData(
              street: Street.flop,
              communityCards: ['Ks', '9h', '4c'],
              actions: [
                HandAction(seat: 2, type: ActionType.check),
                HandAction(seat: 0, type: ActionType.raise, amount: 4),
              ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(equityCheckFacts(check!).any((f) => f.contains('GTO frequency (')),
          isFalse);
    });

    test('out-of-scenario hand → no GTO frequency FACT even with a library',
        () async {
      final check = await computeHandEquityCheck(
        _hand(heroSeat: 2, heroCards: ['As', 'Ah'], villainSeat: 5, streets: [
          const StreetData(street: Street.preflop, actions: [
            HandAction(seat: 2, type: ActionType.post, amount: 2),
            HandAction(seat: 5, type: ActionType.raise, amount: 5), // CO (not late)
            HandAction(seat: 2, type: ActionType.call, amount: 5),
          ]),
          const StreetData(
              street: Street.flop,
              communityCards: ['Ks', '9h', '4c'],
              actions: [
                HandAction(seat: 2, type: ActionType.check),
                HandAction(seat: 5, type: ActionType.raise, amount: 4),
                HandAction(seat: 2, type: ActionType.call, amount: 4),
              ]),
        ]),
        iterations: 500,
        seed: 1,
      );
      expect(
          equityCheckFacts(check!, library: lib)
              .any((f) => f.contains('GTO frequency (')),
          isFalse);
    });

    test('multiway pot facing a bet emits a multiway tendency FACT (no %)',
        () async {
      final check = await computeHandEquityCheck(
        _hand(
          heroSeat: 2,
          heroCards: ['As', 'Ah'],
          villainSeat: 0,
          extraPlayers: const [
            HandPlayer(seatIndex: 5, name: 'V2', startingStack: 200),
          ],
          streets: [
            const StreetData(street: Street.preflop, actions: [
              HandAction(seat: 2, type: ActionType.post, amount: 2),
              HandAction(seat: 5, type: ActionType.raise, amount: 5),
              HandAction(seat: 0, type: ActionType.call, amount: 5),
              HandAction(seat: 2, type: ActionType.call, amount: 5),
            ]),
            const StreetData(
                street: Street.flop,
                communityCards: ['Ks', '9h', '4c'],
                actions: [
                  HandAction(seat: 2, type: ActionType.check),
                  HandAction(seat: 5, type: ActionType.raise, amount: 10),
                  HandAction(seat: 0, type: ActionType.call, amount: 10),
                  HandAction(seat: 2, type: ActionType.call, amount: 10),
                ]),
          ],
        ),
        iterations: 500,
        seed: 1,
      );
      final facts = equityCheckFacts(check!, library: lib);
      final mw = facts.where((f) => f.contains('multiway tendency')).toList();
      expect(mw, hasLength(1));
      expect(mw.first, contains('3-way'));
      expect(mw.first, contains('MDF'));
      expect(facts.any((f) => f.contains('GTO frequency (')), isFalse);
    });
  });
}
