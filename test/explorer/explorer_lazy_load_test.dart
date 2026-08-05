import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/pack_source.dart';
import 'package:tablelab/providers/explorer_provider.dart';
import 'package:tablelab/services/analytics_service.dart';

import '../../tool/solver/explorer_pack.dart';

/// Lazy two-level discovery in the notifier: init() resolves the catalog then
/// loads ONLY the first scenario + auto-selects, ensureScenario dedups
/// concurrent fetches and records retryable failures, and selectSpot's keyed
/// client LRU serves a board-hop return from memory.
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
          'CHECK': terminal(),
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

class _CountingSource implements PackSource {
  final PackSource inner;
  int reads = 0;
  _CountingSource(this.inner);
  @override
  Future<Uint8List> read(String relPath) {
    reads++;
    return inner.read(relPath);
  }
}

class _ThrowingSource implements PackSource {
  @override
  Future<Uint8List> read(String relPath) async =>
      throw StateError('read failed: $relPath');
}

class _FakeDiscovery implements SpotDiscovery {
  List<ScenarioSummary> cat;
  final Map<String, List<ExplorerSpotRef>> spotsByKey;
  final Set<String> failKeys = {};
  int catalogCalls = 0;
  final Map<String, int> scenarioCalls = {};
  Completer<void>? holdCatalog; // when set, catalog() awaits it
  Completer<void>? holdSpots; // when set, scenarioSpots() awaits it

  _FakeDiscovery(this.cat, this.spotsByKey);

  @override
  Future<List<ScenarioSummary>> catalog() async {
    catalogCalls++;
    final h = holdCatalog;
    if (h != null) await h.future;
    return cat;
  }

  @override
  Future<List<ExplorerSpotRef>> scenarioSpots(String key) async {
    scenarioCalls[key] = (scenarioCalls[key] ?? 0) + 1;
    final h = holdSpots;
    if (h != null) await h.future;
    if (failKeys.contains(key)) throw StateError('index fetch failed: $key');
    return spotsByKey[key] ?? const [];
  }
}

void main() {
  late Directory tmp;
  late ExplorerSpotRef packSpot;

  setUpAll(() {
    AnalyticsService.debugDisableForTests = true;
    tmp = Directory.systemTemp.createTempSync('lazytest_');
    generatePack(
      _dump(),
      board: [_c('Ks'), _c('9h'), _c('4c')],
      pot0: 10,
      effStack: 45,
      scenario: 'a_scen',
      sprName: 'medium',
      outDir: tmp.path,
    );
    packSpot = ExplorerSpotRef(
      scenario: 'a_scen',
      flop: 'Ks 9h 4c',
      spr: 'medium',
      source: LocalDirPackSource(tmp.path),
    );
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  ScenarioSummary sum(String key, int n) =>
      ScenarioSummary(key: key, spotCount: n);

  test('init(): catalog → first scenario only → auto-select first spot',
      () async {
    final d = _FakeDiscovery([
      sum('a_scen', 1),
      sum('b_scen', 1),
    ], {
      'a_scen': [packSpot],
      'b_scen': [packSpot],
    });
    final n = ExplorerNotifier()..debugDiscovery = d;
    await n.init();

    expect(n.state.scanning, isFalse);
    expect(n.state.scenarioKeys, {'a_scen', 'b_scen'});
    expect(n.state.spotsFor('a_scen'), hasLength(1));
    // Lazy: the second scenario is NOT fetched by init.
    expect(d.scenarioCalls['b_scen'], isNull);
    expect(n.state.scenarioSpots.containsKey('b_scen'), isFalse);
    // Auto-select landed and loaded the pack.
    expect(n.state.spot, packSpot);
    expect(n.state.manifest, isNotNull);
    expect(n.state.flopNodes, isNotNull);
  });

  test('init() is idempotent mid-flight and after completion', () async {
    final d = _FakeDiscovery([sum('a_scen', 1)], {
      'a_scen': [packSpot]
    });
    d.holdCatalog = Completer<void>();
    final n = ExplorerNotifier()..debugDiscovery = d;
    final first = n.init();
    final second = n.init(); // mid-flight → no-op (scanning guard)
    d.holdCatalog!.complete();
    await Future.wait([first, second]);
    expect(d.catalogCalls, 1);
    await n.init(); // after completion → no-op (catalog.isNotEmpty guard)
    expect(d.catalogCalls, 1);
  });

  test('catalog failure → empty catalog (tab hidden) and init() retries',
      () async {
    final d = _FakeDiscovery(const [], {});
    final n = ExplorerNotifier()..debugDiscovery = d;
    await n.init();
    expect(n.state.catalog, isEmpty); // hidden-tab state
    expect(n.state.scanning, isFalse);
    expect(n.state.spot, isNull);

    // The host recovers → a later init() retries and succeeds.
    d.cat = [sum('a_scen', 1)];
    d.spotsByKey['a_scen'] = [packSpot];
    await n.init();
    expect(d.catalogCalls, 2);
    expect(n.state.catalog, hasLength(1));
    expect(n.state.spot, packSpot);
  });

  test('concurrent ensureScenario calls share ONE fetch', () async {
    final d = _FakeDiscovery([
      sum('a_scen', 1),
      sum('b_scen', 1),
    ], {
      'a_scen': [packSpot],
      'b_scen': [packSpot],
    });
    final n = ExplorerNotifier()..debugDiscovery = d;
    await n.init();

    d.holdSpots = Completer<void>();
    final f1 = n.ensureScenario('b_scen');
    final f2 = n.ensureScenario('b_scen');
    d.holdSpots!.complete();
    await Future.wait([f1, f2]);
    expect(d.scenarioCalls['b_scen'], 1);
    expect(n.state.spotsFor('b_scen'), hasLength(1));
    // Loaded → a further call is a no-op, not a refetch.
    await n.ensureScenario('b_scen');
    expect(d.scenarioCalls['b_scen'], 1);
  });

  test('a failed index fetch records scenarioErrors; retry refetches',
      () async {
    final d = _FakeDiscovery([
      sum('a_scen', 1),
      sum('b_scen', 1),
    ], {
      'a_scen': [packSpot],
      'b_scen': [packSpot],
    });
    final n = ExplorerNotifier()..debugDiscovery = d;
    await n.init();

    d.failKeys.add('b_scen');
    await n.ensureScenario('b_scen');
    expect(n.state.scenarioErrors, {'b_scen'});
    expect(n.state.scenarioSpots.containsKey('b_scen'), isFalse);
    expect(d.scenarioCalls['b_scen'], 1);

    // Retry actually refetches (the failed future was cleared) and clears
    // the error on success.
    d.failKeys.remove('b_scen');
    await n.ensureScenario('b_scen');
    expect(d.scenarioCalls['b_scen'], 2);
    expect(n.state.scenarioErrors, isEmpty);
    expect(n.state.spotsFor('b_scen'), hasLength(1));
  });

  test('ensureScenario before init() is a no-op that does NOT wedge the key',
      () async {
    final d = _FakeDiscovery([sum('a_scen', 1)], {
      'a_scen': [packSpot]
    });
    final n = ExplorerNotifier()..debugDiscovery = d;
    // Pre-init: no discovery yet — must complete without caching a dead
    // future for the key (the wedge was: cleanup ran before ??= stored it).
    await n.ensureScenario('a_scen');
    expect(d.scenarioCalls['a_scen'], isNull);
    expect(n.state.scenarioSpots.containsKey('a_scen'), isFalse);

    await n.init();
    expect(n.state.spotsFor('a_scen'), hasLength(1));
    expect(n.state.spot, packSpot);
  });

  test('a spot whose source throws is NOT cached in the client LRU', () async {
    final n = ExplorerNotifier();
    final bad = ExplorerSpotRef(
      scenario: 'a_scen',
      flop: 'Ks 9h 4c',
      spr: 'broken',
      source: _ThrowingSource(),
    );
    await n.selectSpot(bad);
    expect(n.state.error, isNotNull);
    expect(n.debugClientCacheCount, 0); // never-loaded client dropped
  });

  test('selectSpot client LRU: caps at 8, reuses on a return visit', () async {
    final counting = _CountingSource(LocalDirPackSource(tmp.path));
    // Distinct ids (spr varies) over one shared pack — identity is what the
    // LRU keys on, not the bytes.
    ExplorerSpotRef mk(int i) => ExplorerSpotRef(
          scenario: 'a_scen',
          flop: 'Ks 9h 4c',
          spr: 'r$i',
          source: counting,
        );
    final n = ExplorerNotifier();
    final spots = [for (var i = 0; i < 9; i++) mk(i)];
    for (final s in spots) {
      await n.selectSpot(s);
    }
    expect(n.debugClientCacheCount, 8); // spot 0 evicted (LRU)

    final readsBefore = counting.reads;
    await n.selectSpot(spots[8]); // cached client → zero refetch
    expect(counting.reads, readsBefore);

    await n.selectSpot(spots[0]); // evicted → refetches
    expect(counting.reads, greaterThan(readsBefore));
    expect(n.debugClientCacheCount, 8);
  });
}
