import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';

import '../../tool/solver/explorer_pack.dart';

List<int> _b(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

/// A hand-constructed dump with `ev`/`ev_passive` maps (the patched-solver
/// fields) on the ROOT node only — the IP node deliberately lacks them, locking
/// the NA path. Flop Ks9h4c: OOP {QcQd, 7c2d} acts first, IP {AdAh} responds;
/// the CHECK/CHECK line reaches a 2s turn (reach-weighting check: QQ arrives
/// 0.5, 72o arrives 0.8).
Map<String, dynamic> _dump() => {
      'node_type': 'action_node',
      'player': 0, // OOP
      'strategy': {
        'actions': ['CHECK', 'BET 5', 'BET 15'],
        'strategy': {
          'Qc Qd': [0.5, 0.3, 0.2],
          '7c 2d': [0.8, 0.1, 0.1],
        },
      },
      'ev': {
        'Qc Qd': [1.2, 2.4, -0.5],
        '7c 2d': [0.1, 0.2, 0.3],
      },
      'ev_passive': {
        'Qc Qd': [1.1],
        '7c 2d': [0.05],
      },
      'childrens': {
        'CHECK': {
          'node_type': 'action_node',
          'player': 1, // IP, facing OOP's check — NO ev/ev_passive here
          'strategy': {
            'actions': ['CHECK', 'BET 8'],
            'strategy': {
              'Ad Ah': [0.7, 0.3],
            },
          },
          'childrens': {
            'CHECK': {
              'node_type': 'chance_node',
              'dealcards': {
                '2s': {
                  'node_type': 'action_node',
                  'player': 0, // OOP, turn
                  'strategy': {
                    'actions': ['CHECK', 'BET 10'],
                    'strategy': {
                      'Qc Qd': [0.4, 0.6],
                      '7c 2d': [0.9, 0.1],
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

void main() {
  late Directory tmp;
  late Map<String, dynamic> manifest;
  late PackStats stats;

  List<PackNode> readChunk(String id) {
    final file = File('${tmp.path}/$id.bin.gz');
    expect(file.existsSync(), isTrue, reason: 'missing chunk $id');
    return decodeChunk(gzip.decode(file.readAsBytesSync()));
  }

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('packtest_');
    final r = generatePack(_dump(),
        board: _b('Ks 9h 4c'),
        pot0: 10,
        effStack: 45,
        scenario: 'srp_late_v_bb',
        sprName: 'medium',
        outDir: tmp.path);
    manifest = r.manifest;
    stats = r.stats;
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('manifest combo lists are sorted and position-correct', () {
    final combos = manifest['combos'] as Map<String, dynamic>;
    expect(combos['oop'], ['7c2d', 'QdQc']);
    expect(combos['ip'], ['AhAd']);
  });

  test('chunk files exist per street with the right node counts', () {
    final chunks = manifest['chunks'] as Map<String, dynamic>;
    expect(chunks.keys, containsAll(['flop', 'turn/2s']));
    expect((chunks['flop'] as Map)['nodes'], 2); // OOP root + IP response
    expect((chunks['turn/2s'] as Map)['nodes'], 1);
    expect(stats.actionNodes, 3);
  });

  test('root node round-trips: path, chip state, actions, freqs, EVs', () {
    final flop = readChunk('flop');
    final root = flop.firstWhere((n) => n.path.isEmpty);
    expect(root.street, 0);
    expect(root.actorIsOop, isTrue);
    expect(root.potBefore, closeTo(10, 1e-6));
    expect(root.toCall, closeTo(0, 1e-6));
    expect(root.behind, closeTo(45, 1e-6));
    expect(root.actions, ['CHECK', 'BET 5', 'BET 15']);

    // Registry-ordered combos: 7c2d = id 0, QdQc = id 1, both reach 1.0.
    expect(root.combos.map((c) => c.comboId), [0, 1]);
    final qq = root.combos[1];
    expect(qq.reach, closeTo(1.0, 1e-4));
    expect(qq.freqs[0], closeTo(0.5, 1 / 250));
    expect(qq.freqs[1], closeTo(0.3, 1 / 250));
    expect(qq.freqs[2], closeTo(0.2, 1 / 250));
    // EV ×20 quantization is exact for these values.
    expect(qq.evs, [1.2, 2.4, -0.5]);
    expect(qq.evPassive, 1.1);
    expect(stats.nodesWithEv, 1);
    expect(stats.nodesWithPassiveEv, 1);
  });

  test('a node without ev/ev_passive decodes to NA (nulls)', () {
    final flop = readChunk('flop');
    final ipNode = flop.firstWhere((n) => n.path == 'CHECK');
    expect(ipNode.actorIsOop, isFalse);
    final aa = ipNode.combos.single;
    expect(aa.evs, [null, null]);
    expect(aa.evPassive, isNull);
  });

  test('turn reach carries the flop check frequencies (reach-weighting)', () {
    final turn = readChunk('turn/2s');
    final node = turn.single;
    expect(node.path, 'CHECK/CHECK/@2s');
    expect(node.street, 1);
    final byId = {for (final c in node.combos) c.comboId: c};
    expect(byId[1]!.reach, closeTo(0.5, 1e-3)); // QQ checked 50%
    expect(byId[0]!.reach, closeTo(0.8, 1e-3)); // 72o checked 80%
  });

  test('equity is sane: AA (vs the check range) beats QQ (vs AA)', () {
    final flop = readChunk('flop');
    final root = flop.firstWhere((n) => n.path.isEmpty);
    final ipNode = flop.firstWhere((n) => n.path == 'CHECK');
    final qqEq = root.combos[1].equity;
    final aaEq = ipNode.combos.single.equity;
    expect(qqEq, isNotNull);
    expect(aaEq, isNotNull);
    expect(qqEq!, inExclusiveRange(0.0, 1.0));
    expect(aaEq!, inExclusiveRange(0.0, 1.0));
    expect(aaEq, greaterThan(0.8)); // overpair vs {QQ, 72o} on K94r
    expect(qqEq, lessThan(0.2)); // QQ drawing ~2 outs vs AA
    expect(aaEq, greaterThan(qqEq));
  });

  test('turn equity conditions on the dealt card (no NA on live combos)', () {
    final turn = readChunk('turn/2s');
    for (final c in turn.single.combos) {
      expect(c.equity, isNotNull);
      expect(c.equity!, inExclusiveRange(0.0, 1.0));
    }
  });
}
