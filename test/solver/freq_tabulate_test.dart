import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';

import '../../tool/solver/freq_tabulate.dart';

List<int> _b(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

/// A hand-constructed dump: flop Ks9h4c, OOP first to act. The CHECK line leads
/// (via an IP check and a 2s turn) to an OOP turn node, so we can verify reach-
/// weighting: QcQd checks the flop 50%, 7c2d checks 80%, and both are marginal-
/// made on the turn — the turn aggregate must skew toward 7c2d's mix.
Map<String, dynamic> _dump() => {
      'node_type': 'action_node',
      'player': 0, // OOP
      'strategy': {
        'actions': ['CHECK', 'BET 5', 'BET 15'],
        'strategy': {
          'Qc Qd': [0.5, 0.3, 0.2], // marginalMade (one pair QQ)
          '7c 2d': [0.8, 0.1, 0.1], // air
        },
      },
      'childrens': {
        'CHECK': {
          'node_type': 'action_node',
          'player': 1, // IP, facing OOP's check
          'strategy': {
            'actions': ['CHECK', 'BET 8'],
            'strategy': {
              'Ad Ah': [0.7, 0.3], // marginalMade (overpair)
            },
          },
          'childrens': {
            'CHECK': {
              'node_type': 'chance_node',
              // Real solver dumps key a chance node's cards under `dealcards`,
              // NOT `childrens` — the tabulator must read dealcards (regression).
              'dealcards': {
                '2s': {
                  'node_type': 'action_node',
                  'player': 0, // OOP, new street (turn)
                  'strategy': {
                    'actions': ['CHECK', 'BET 10'],
                    'strategy': {
                      'Qc Qd': [0.4, 0.6], // still one pair → marginalMade
                      '7c 2d': [0.9, 0.1], // now pairs the 2 → marginalMade
                    },
                  },
                  'childrens': {
                    'CHECK': {'node_type': 'terminal_node'},
                    'BET 10': {'node_type': 'terminal_node'},
                  },
                },
              },
            },
            'BET 8': {'node_type': 'terminal_node'},
          },
        },
        'BET 5': {'node_type': 'terminal_node'},
        'BET 15': {'node_type': 'terminal_node'},
      },
    };

FreqCell _cell(List<FreqCell> cells,
    {required String street,
    required String position,
    required String facing,
    required String handClass}) {
  return cells.firstWhere((c) =>
      c.street == street &&
      c.position == position &&
      c.facing == facing &&
      c.handClass == handClass);
}

void main() {
  group('canonicalActionLabels', () {
    test('ranks bet sizes to small/big and maps the rest', () {
      expect(canonicalActionLabels(['CHECK', 'BET 5', 'BET 15']),
          ['check', 'bet_small', 'bet_big']);
      expect(canonicalActionLabels(['FOLD', 'CALL', 'RAISE 60', 'ALLIN']),
          ['fold', 'call', 'raise', 'allin']);
    });

    test('a lone bet size is just "bet"', () {
      expect(canonicalActionLabels(['CHECK', 'BET 8']), ['check', 'bet']);
    });

    test('three bet sizes give small/mid/big', () {
      expect(canonicalActionLabels(['BET 3', 'BET 9', 'BET 20']),
          ['bet_small', 'bet_mid', 'bet_big']);
    });
  });

  group('tabulateSpot', () {
    // pot0 10, effStack 45 → flop SPR 4.5 → 'medium'. The turn is reached via
    // CHECK→CHECK (no chips added), so the turn SPR is still 4.5 → 'medium'.
    final cells = tabulateSpot(_dump(),
        board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);

    test('flop OOP cells carry each combo mix verbatim (reach 1.0)', () {
      final mm = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(mm.texture, 'rainbow|unpaired|broadway|disconnected');
      expect(mm.freqs['check'], closeTo(0.5, 1e-9));
      expect(mm.freqs['bet_small'], closeTo(0.3, 1e-9));
      expect(mm.freqs['bet_big'], closeTo(0.2, 1e-9));
      expect(mm.reachWeight, closeTo(1.0, 1e-9));

      final air = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'air');
      expect(air.freqs['check'], closeTo(0.8, 1e-9));
    });

    test('IP node is tagged position=ip, facing=facing_check', () {
      final ip = _cell(cells,
          street: 'flop',
          position: 'ip',
          facing: 'facing_check',
          handClass: 'marginalMade');
      expect(ip.freqs['check'], closeTo(0.7, 1e-9));
      expect(ip.freqs['bet'], closeTo(0.3, 1e-9));
    });

    test('turn cell texture is recomputed (rainbow → twotone after 2s)', () {
      final t = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(t.texture, 'twotone|unpaired|broadway|disconnected');
    });

    test('a checked-through turn keeps the flop SPR bucket (medium)', () {
      final flop = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      final turn = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(flop.sprBucket, 'medium');
      expect(turn.sprBucket, 'medium'); // CHECK→CHECK adds no chips
    });

    test('turn aggregate is REACH-weighted by flop-check frequency', () {
      // QcQd reaches the turn-check node with reach 0.5, 7c2d with 0.8.
      //   check = (0.5·0.4 + 0.8·0.9) / (0.5+0.8) = 0.92/1.3 = 0.70769…
      //   bet   = (0.5·0.6 + 0.8·0.1) / 1.3        = 0.38/1.3 = 0.29231…
      // A naive (unweighted) average would give check 0.65 — distinct, so this
      // pins the reach-weighting, not just an average.
      final t = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(t.freqs['check'], closeTo(0.92 / 1.3, 1e-6));
      expect(t.freqs['bet'], closeTo(0.38 / 1.3, 1e-6));
      expect(t.reachWeight, closeTo(1.3, 1e-9));
      expect(t.freqs['check'], isNot(closeTo(0.65, 1e-2)));
    });

    test('maxBoardLen caps the walk depth (no turn cells at flop-only)', () {
      final flopOnly = tabulateSpot(_dump(),
          board: _b('Ks 9h 4c'), pot0: 10, effStack: 45, maxBoardLen: 3);
      expect(flopOnly.any((c) => c.street == 'turn'), isFalse);
      expect(flopOnly.any((c) => c.street == 'flop'), isTrue);
    });
  });

  // A bet-call flop line grows the pot and shrinks stacks, so the turn sits in a
  // SHALLOWER SPR bucket than the flop — the cell must be tagged by its own
  // street's SPR (what the live villain_range path computes), not the flop regime.
  group('tabulateSpot per-street SPR', () {
    // flop Ks9h4c, pot 10, effStack 60 → flop SPR 6 → 'medium'.
    // OOP bets 7.5 (75% pot), IP calls → pot 25, each committed 7.5,
    // remaining 52.5 → turn SPR 52.5/25 = 2.1 → 'shallow'.
    Map<String, dynamic> betCallDump() => {
          'node_type': 'action_node',
          'player': 0, // OOP
          'strategy': {
            'actions': ['CHECK', 'BET 7.5'],
            'strategy': {
              'Qc Qd': [0.3, 0.7], // marginalMade
            },
          },
          'childrens': {
            'CHECK': {'node_type': 'terminal_node'},
            'BET 7.5': {
              'node_type': 'action_node',
              'player': 1, // IP, facing the bet
              'strategy': {
                'actions': ['FOLD', 'CALL'],
                'strategy': {
                  'Ad Ah': [0.2, 0.8],
                },
              },
              'childrens': {
                'FOLD': {'node_type': 'terminal_node'},
                'CALL': {
                  'node_type': 'chance_node',
                  'dealcards': {
                    '2c': {
                      'node_type': 'action_node',
                      'player': 0, // OOP, turn
                      'strategy': {
                        'actions': ['CHECK', 'BET 12'],
                        'strategy': {
                          'Qc Qd': [0.5, 0.5], // still one pair → marginalMade
                        },
                      },
                      'childrens': {
                        'CHECK': {'node_type': 'terminal_node'},
                        'BET 12': {'node_type': 'terminal_node'},
                      },
                    },
                  },
                },
              },
            },
          },
        };

    final cells =
        tabulateSpot(betCallDump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 60);

    test('flop is medium, turn drops to shallow after a 75%-pot bet-call', () {
      final flop = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      final turn = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(flop.sprBucket, 'medium');
      expect(turn.sprBucket, 'shallow');
    });
  });

  // A faced bet's `facing` key must use ABSOLUTE pot-fraction size buckets
  // (shared betSizeBucket: small <=45%, mid <=70%, big) — NOT the bare 'bet' that
  // canonicalActionLabels emits for a single-size tree — or the live lookup (which
  // keys facing on facing_bet_small/mid/big) can never reach the cell.
  group('tabulateSpot facing-bet size bucketing', () {
    // Flop checks through → turn pot 10. OOP leads turn for 6.6 (66% = 'mid');
    // IP faces it, so IP's node is tagged facing_bet_mid, not facing_bet.
    Map<String, dynamic> turnLeadDump() => {
          'node_type': 'action_node',
          'player': 0, // OOP flop
          'strategy': {
            'actions': ['CHECK', 'BET 5'],
            'strategy': {'Qc Qd': [1.0, 0.0]},
          },
          'childrens': {
            'CHECK': {
              'node_type': 'action_node',
              'player': 1, // IP flop, facing check
              'strategy': {
                'actions': ['CHECK', 'BET 5'],
                'strategy': {'Ad Ah': [1.0, 0.0]},
              },
              'childrens': {
                'CHECK': {
                  'node_type': 'chance_node',
                  'dealcards': {
                    '2c': {
                      'node_type': 'action_node',
                      'player': 0, // OOP turn, leads
                      'strategy': {
                        'actions': ['CHECK', 'BET 6.6'],
                        'strategy': {'Qc Qd': [0.4, 0.6]},
                      },
                      'childrens': {
                        'CHECK': {'node_type': 'terminal_node'},
                        'BET 6.6': {
                          'node_type': 'action_node',
                          'player': 1, // IP turn, FACING the 66% bet
                          'strategy': {
                            'actions': ['FOLD', 'CALL'],
                            'strategy': {'Ad Ah': [0.3, 0.7]},
                          },
                          'childrens': {
                            'FOLD': {'node_type': 'terminal_node'},
                            'CALL': {'node_type': 'terminal_node'},
                          },
                        },
                      },
                    },
                  },
                },
                'BET 5': {'node_type': 'terminal_node'},
              },
            },
            'BET 5': {'node_type': 'terminal_node'},
          },
        };

    final cells =
        tabulateSpot(turnLeadDump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 60);

    test('faced 66%-pot turn bet is tagged facing_bet_mid (not bare facing_bet)', () {
      final faced = cells.where((c) => c.street == 'turn' && c.position == 'ip');
      expect(faced.map((c) => c.facing), contains('facing_bet_mid'));
      expect(faced.map((c) => c.facing), isNot(contains('facing_bet')));
    });
  });
}
