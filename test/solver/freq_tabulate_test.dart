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
    final cells = tabulateSpot(_dump(),
        board: _b('Ks 9h 4c'), sprBucket: 'medium');

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
          board: _b('Ks 9h 4c'), sprBucket: 'medium', maxBoardLen: 3);
      expect(flopOnly.any((c) => c.street == 'turn'), isFalse);
      expect(flopOnly.any((c) => c.street == 'flop'), isTrue);
    });
  });
}
