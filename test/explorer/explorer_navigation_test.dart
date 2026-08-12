import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/pack_source.dart';
import 'package:tablelab/providers/explorer_provider.dart';
import 'package:tablelab/services/analytics_service.dart';

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
    // These tests drive selectSpot directly; without this the analytics
    // capture hits an unregistered method channel on macOS hosts (posthog
    // only no-ops on Windows/Linux) and throws into the test zone.
    AnalyticsService.debugDisableForTests = true;
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

    await n.advance('CHECK');
    await n.advance('CHECK');
    expect(n.state.currentNode, isNull); // flop closed
    expect(n.state.dealtCards, isEmpty);

    await n.pickCard('2s');
    expect(n.state.dealtCards, ['2s']);
    final turnNode = n.state.currentNode;
    expect(turnNode, isNotNull, reason: 'turn chunk should load lazily');
    expect(turnNode!.street, 1);
    expect(turnNode.path, 'CHECK/CHECK/@2s');

    await n.advance('CHECK');
    await n.advance('CHECK');
    expect(n.state.currentNode, isNull); // turn closed

    await n.pickCard('3d');
    final riverNode = n.state.currentNode;
    expect(riverNode, isNotNull);
    expect(riverNode!.street, 2);
    expect(riverNode.path, 'CHECK/CHECK/@2s/CHECK/CHECK/@3d');
    expect(riverNode.actions, ['CHECK', 'BET 7']);
  });

  test('the line PERSISTS: cursor moves freely without resetting anything',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('2s');
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('3d');
    expect(n.state.line,
        ['CHECK', 'CHECK', '@2s', 'CHECK', 'CHECK', '@3d']);

    // Jump back to the flop root — the LINE is untouched, chunks stay.
    n.setCursor(0);
    expect(n.state.line, ['CHECK', 'CHECK', '@2s', 'CHECK', 'CHECK', '@3d']);
    expect(n.state.dealtCards, isEmpty); // board at the cursor = flop
    expect(n.state.currentNode!.street, 0);
    expect(n.state.turnNodes, isNotNull); // nothing reset
    expect(n.state.recordedNext, 'CHECK');

    // Jump straight to the river decision (cursor normalizes off '@').
    n.setCursor(5);
    expect(n.state.currentNode!.street, 2);
    expect(n.state.dealtCards, ['2s', '3d']);

    // REPLAY from the flop by taking the recorded action — pure cursor moves.
    n.setCursor(0);
    await n.advance('CHECK'); // matches recorded → replay
    expect(n.state.cursor, 1);
    expect(n.state.line, hasLength(6)); // unchanged
    await n.advance('CHECK'); // closes the flop; cursor skips '@2s'
    expect(n.state.cursor, 3);
    expect(n.state.currentNode!.street, 1); // turn node, no re-pick needed
  });

  test('EDITING mid-line rewrites from the cursor and regrows the valid tail',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('2s');
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('3d');

    // Go back to the SECOND flop decision (IP) and change CHECK → BET 5.
    n.setCursor(1);
    await n.advance('BET 5');
    // The IP bet invalidates the rest (OOP now faces a bet; the old tail's
    // next step '@2s' needs a CLOSED street): line = prefix + edit only.
    expect(n.state.line, ['CHECK', 'BET 5']);
    expect(n.state.cursor, 2);
    // Pins survive the edit (cards are never re-entered).
    expect(n.state.turnCard, '2s');
    expect(n.state.riverCard, '3d');
  });

  test('EDITING with a tail that stays valid keeps it', () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('2s');
    await n.advance('CHECK');
    await n.advance('CHECK');

    // Replay to the turn root and re-take the SAME action via advance — no
    // edit; then edit the FIRST turn action CHECK → BET 6: the tail (CHECK)
    // is invalid vs a bet (opponent faces BET 6, whose node isn't in this
    // synthetic dump), so the line truncates there.
    n.setCursor(3);
    await n.advance('BET 6');
    expect(n.state.line, ['CHECK', 'CHECK', '@2s', 'BET 6']);
    expect(n.state.turnCard, '2s'); // pin untouched
  });

  test('a runout absent from the pack leaves an unavailable (null) node',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('7d'); // dump only carries the 2s turn
    expect(n.state.dealtCards, ['7d']);
    expect(n.state.currentNode, isNull);
    expect(n.state.chunkLoading, isFalse);
  });

  test('setPinnedCard swaps a dealt card IN PLACE, keeping the line', () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('7d'); // absent runout → unavailable
    expect(n.state.currentNode, isNull);

    await n.setPinnedCard(river: false, card: '2s'); // swap to the real turn
    expect(n.state.line, ['CHECK', 'CHECK', '@2s']); // line preserved
    expect(n.state.turnCard, '2s');
    expect(n.state.currentNode, isNotNull); // chunk refetched
    expect(n.state.currentNode!.street, 1);
  });

  test('setPinnedCard before the street is reached only pins', () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.setPinnedCard(river: false, card: '2s'); // at the flop root
    expect(n.state.line, isEmpty);
    expect(n.state.turnCard, '2s');
    expect(n.state.currentNode, isNotNull); // still the flop root
    expect(n.state.currentNode!.street, 0);
  });

  test('changing the TURN clears the pinned river; identical re-pick keeps it',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('2s');
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('3d');
    expect(n.state.line,
        ['CHECK', 'CHECK', '@2s', 'CHECK', 'CHECK', '@3d']);

    // Re-pick the IDENTICAL turn card → the river survives untouched.
    await n.setPinnedCard(river: false, card: '2s');
    expect(n.state.line,
        ['CHECK', 'CHECK', '@2s', 'CHECK', 'CHECK', '@3d']);
    expect(n.state.turnCard, '2s');
    expect(n.state.riverCard, '3d');

    // Change the turn to a DIFFERENT card → the pinned river CLEARS and the
    // line truncates at the river deal (river street un-dealt: dealtCards has
    // one entry, so the strip's river box falls back to its '+' state).
    await n.setPinnedCard(river: false, card: '7d');
    expect(n.state.line, ['CHECK', 'CHECK', '@7d', 'CHECK', 'CHECK']);
    expect(n.state.turnCard, '7d');
    expect(n.state.riverCard, isNull);
    expect(n.state.riverNodes, isNull);
    expect(n.state.cursor, lessThanOrEqualTo(n.state.line.length));
    expect(n.state.dealtCards, ['7d']);
  });

  test('the old river card is a LEGAL new turn pick (river cleared)',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('2s');
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('3d');

    // The pinned river 3d as the NEW turn: no collision guard fires — the
    // river is cleared by the same change.
    await n.setPinnedCard(river: false, card: '3d');
    expect(n.state.turnCard, '3d');
    expect(n.state.riverCard, isNull);
    expect(n.state.line, ['CHECK', 'CHECK', '@3d', 'CHECK', 'CHECK']);
  });

  test('a NEW turn pick at the line end clears a leftover river pin',
      () async {
    final n = ExplorerNotifier();
    await n.selectSpot(spot);
    // River pinned ahead of time (before any street is dealt).
    await n.setPinnedCard(river: true, card: '3d');
    expect(n.state.riverCard, '3d');
    await n.advance('CHECK');
    await n.advance('CHECK');
    await n.pickCard('2s'); // turn differs from the (null) turn pin
    expect(n.state.turnCard, '2s');
    expect(n.state.riverCard, isNull);
  });
}
