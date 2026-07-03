import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/pack_source.dart';
import 'package:tablelab/providers/explorer_provider.dart';

import '../../tool/solver/explorer_pack.dart';

/// Street navigation over a REAL generated multi-street pack: flop checks
/// through → deal the turn (lazy 'turn/2s' chunk) → turn checks through →
/// deal the river ('river/2s3d') → river node reached. Locks the chance-step
/// path convention ('@2s') between generator and provider, plus rewind
/// clearing and the missing-runout fallback.
Map<String, dynamic> _dump() {
  Map<String, dynamic> terminal() => {'node_type': 'terminal_node'};
  return {
    'node_type': 'action_node',
    'player': 0,
    'strategy': {
      'actions': ['CHECK', 'BET 5'],
      'strategy': {
        'Kc Qd': [1.0, 0.0],
      },
    },
    'childrens': {
      'BET 5': terminal(),
      'CHECK': {
        'node_type': 'action_node',
        'player': 1,
        'strategy': {
          'actions': ['CHECK', 'BET 5'],
          'strategy': {
            'Ad Ah': [1.0, 0.0],
          },
        },
        'childrens': {
          'BET 5': terminal(),
          'CHECK': {
            'node_type': 'chance_node',
            'dealcards': {
              '2s': {
                'node_type': 'action_node',
                'player': 0,
                'strategy': {
                  'actions': ['CHECK', 'BET 6'],
                  'strategy': {
                    'Kc Qd': [1.0, 0.0],
                  },
                },
                'childrens': {
                  'BET 6': terminal(),
                  'CHECK': {
                    'node_type': 'action_node',
                    'player': 1,
                    'strategy': {
                      'actions': ['CHECK', 'BET 6'],
                      'strategy': {
                        'Ad Ah': [1.0, 0.0],
                      },
                    },
                    'childrens': {
                      'BET 6': terminal(),
                      'CHECK': {
                        'node_type': 'chance_node',
                        'dealcards': {
                          '3d': {
                            'node_type': 'action_node',
                            'player': 0,
                            'strategy': {
                              'actions': ['CHECK', 'BET 7'],
                              'strategy': {
                                'Kc Qd': [0.6, 0.4],
                              },
                            },
                            'childrens': {
                              'CHECK': terminal(),
                              'BET 7': terminal(),
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  };
}

int _c(String s) {
  const ranks = '23456789TJQKA';
  const suits = 'cdhs';
  return ranks.indexOf(s[0]) * 4 + suits.indexOf(s[1]);
}

void main() {
  late Directory tmp;
  late ExplorerSpotRef spot;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('navtest_');
    generatePack(
      _dump(),
      board: [_c('Ks'), _c('9h'), _c('4c')],
      pot0: 10,
      effStack: 45,
      scenario: 'srp_late_v_bb',
      sprName: 'medium',
      outDir: tmp.path,
    );
    spot = ExplorerSpotRef(
      scenario: 'srp_late_v_bb',
      flop: 'Ks 9h 4c',
      spr: 'medium',
      source: LocalDirPackSource(tmp.path),
    );
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('flop → turn → river navigation with lazy chunk loads', () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    expect(n.state.currentNode, isNotNull); // flop root

    n.push('CHECK');
    n.push('CHECK');
    expect(n.state.currentNode, isNull); // flop closed
    expect(n.state.dealtCards, isEmpty);

    await n.pickCard('2s');
    expect(n.state.dealtCards, ['2s']);
    final turnNode = n.state.currentNode;
    expect(turnNode, isNotNull, reason: 'turn chunk should load lazily');
    expect(turnNode!.street, 1);
    expect(turnNode.path, 'CHECK/CHECK/@2s');

    n.push('CHECK');
    n.push('CHECK');
    expect(n.state.currentNode, isNull); // turn closed

    await n.pickCard('3d');
    final riverNode = n.state.currentNode;
    expect(riverNode, isNotNull);
    expect(riverNode!.street, 2);
    expect(riverNode.path, 'CHECK/CHECK/@2s/CHECK/CHECK/@3d');
    expect(riverNode.actions, ['CHECK', 'BET 7']);
  });

  test('rewinding across a chance step drops the street nodes', () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    n.push('CHECK');
    n.push('CHECK');
    await n.pickCard('2s');
    expect(n.state.turnNodes, isNotNull);

    n.popTo(2); // back to the closed flop, before the turn card
    expect(n.state.dealtCards, isEmpty);
    expect(n.state.turnNodes, isNull);
    expect(n.state.riverNodes, isNull);

    // Re-dealing works (chunk comes from the client LRU).
    await n.pickCard('2s');
    expect(n.state.currentNode, isNotNull);
  });

  test('a runout absent from the pack leaves an unavailable (null) node',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    n.push('CHECK');
    n.push('CHECK');
    await n.pickCard('7d'); // dump only carries the 2s turn
    expect(n.state.dealtCards, ['7d']);
    expect(n.state.currentNode, isNull);
    expect(n.state.chunkLoading, isFalse);
  });

  test('picked cards are PINNED and survive rewinds past the chance step',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    n.push('CHECK');
    n.push('CHECK');
    await n.pickCard('2s');
    n.push('CHECK');
    n.push('CHECK');
    await n.pickCard('3d');
    expect(n.state.turnCard, '2s');
    expect(n.state.riverCard, '3d');

    n.popTo(0); // all the way back to the flop root
    expect(n.state.dealtCards, isEmpty);
    expect(n.state.turnNodes, isNull); // cursor state cleared…
    expect(n.state.turnCard, '2s'); // …but the pins persist
    expect(n.state.riverCard, '3d');
  });

  test('setPinnedCard swaps a dealt card IN PLACE, keeping the line', () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    n.push('CHECK');
    n.push('CHECK');
    await n.pickCard('7d'); // absent runout → unavailable
    expect(n.state.currentNode, isNull);

    await n.setPinnedCard(river: false, card: '2s'); // swap to the real turn
    expect(n.state.path, ['CHECK', 'CHECK', '@2s']); // line preserved
    expect(n.state.turnCard, '2s');
    expect(n.state.currentNode, isNotNull); // chunk refetched
    expect(n.state.currentNode!.street, 1);
  });

  test('setPinnedCard before the street is reached only pins', () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.setPinnedCard(river: false, card: '2s'); // at the flop root
    expect(n.state.path, isEmpty);
    expect(n.state.turnCard, '2s');
    expect(n.state.currentNode, isNotNull); // still the flop root
    expect(n.state.currentNode!.street, 0);
  });
}
