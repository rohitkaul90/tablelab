import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/explorer_client.dart';
import 'package:tablelab/explorer/pack_source.dart';

import '../../tool/solver/explorer_pack.dart';

/// End-to-end: generate a real (mini) pack with the offline generator, then
/// load it back through the APP-side client (LocalDirPackSource → gunzip →
/// decode) — locks that generator and client agree on the wire format.
void main() {
  late Directory tmp;
  late String spotDir;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('clienttest_');
    spotDir = '${tmp.path}/Ks9h4c_medium';
    generatePack(
      {
        'node_type': 'action_node',
        'player': 0,
        'strategy': {
          'actions': ['CHECK', 'BET 5'],
          'strategy': {
            'Qc Qd': [0.5, 0.5],
          },
        },
        'ev': {
          'Qc Qd': [1.2, 2.4],
        },
        'childrens': {
          'CHECK': {'node_type': 'terminal_node'},
          'BET 5': {'node_type': 'terminal_node'},
        },
      },
      board: [parseC('Ks'), parseC('9h'), parseC('4c')],
      pot0: 10,
      effStack: 45,
      scenario: 'srp_late_v_bb',
      sprName: 'medium',
      outDir: spotDir,
    );
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('client loads manifest + flop chunk from a generated pack', () async {
    final client = ExplorerPackClient(LocalDirPackSource(spotDir));
    final manifest = await client.manifest();
    expect(manifest.scenario, 'srp_late_v_bb');
    expect(manifest.flop, 'Ks 9h 4c');
    expect(manifest.spr, 'medium');
    expect(manifest.oopCombos, ['QdQc']);

    final nodes = await client.chunk('flop');
    expect(nodes, hasLength(1));
    final root = nodes.single;
    expect(root.actions, ['CHECK', 'BET 5']);
    expect(root.combos.single.freqs[0], closeTo(0.5, 1 / 250));
    expect(root.combos.single.evs, [1.2, 2.4]);

    // Cached second read returns the same decoded list instance.
    expect(identical(await client.chunk('flop'), nodes), isTrue);
  });

  test('missing chunk id throws a descriptive StateError', () async {
    final client = ExplorerPackClient(LocalDirPackSource(spotDir));
    expect(client.chunk('turn/2c'), throwsStateError);
  });

  test('scanLocalPacks discovers the spot in a flat layout', () async {
    final spots = await scanLocalPacks(tmp.path);
    expect(
      spots.where((s) => s.flop == 'Ks 9h 4c' && s.spr == 'medium'),
      isNotEmpty,
    );
  });

  test('manifest json parses through the model defensively', () {
    final raw = jsonDecode(File('$spotDir/manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(raw['format'], isNotNull); // scales recorded for forward compat
  });
}

/// Tiny local card parser so this test doesn't reach into lib/equity.
int parseC(String s) {
  const ranks = '23456789TJQKA';
  const suits = 'cdhs';
  return ranks.indexOf(s[0]) * 4 + suits.indexOf(s[1]);
}
