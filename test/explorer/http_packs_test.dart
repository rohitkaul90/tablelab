import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tablelab/explorer/http_packs.dart';

/// Hosted discovery must parse the index into spots, tolerate malformed input
/// (return [] — the Study tab just stays hidden), and read chunks from the
/// correct per-spot URL.
void main() {
  test('fetchHostedSpots parses the index into spots with HTTP sources',
      () async {
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://packs.example/index.json');
      return http.Response(
        jsonEncode({
          'version': 1,
          'spots': [
            {
              'scenario': 'srp_late_v_bb',
              'flop': '7s 5s 2s',
              'spr': 'deep',
              'path': 'srp_late_v_bb/7s5s2s_deep'
            },
            {'scenario': 'x', 'flop': 'y'}, // missing spr/path → skipped
          ]
        }),
        200,
      );
    });

    final spots =
        await fetchHostedSpots('https://packs.example/', client: client);
    expect(spots, hasLength(1));
    expect(spots.single.scenario, 'srp_late_v_bb');
    expect(spots.single.flop, '7s 5s 2s');
    expect(spots.single.spr, 'deep');
  });

  test('a non-200 or malformed index yields no spots (never throws)', () async {
    final err = MockClient((req) async => http.Response('nope', 404));
    expect(await fetchHostedSpots('https://packs.example', client: err),
        isEmpty);

    final junk = MockClient((req) async => http.Response('not json {{{', 200));
    expect(await fetchHostedSpots('https://packs.example', client: junk),
        isEmpty);
  });

  test('leading/trailing slashes in an index path are normalized (no //)',
      () async {
    Uri? readUrl;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('index.json')) {
        return http.Response(
          jsonEncode({
            'version': 1,
            'spots': [
              {'scenario': 's', 'flop': 'f', 'spr': 'p', 'path': '/scen/spot/'}
            ]
          }),
          200,
        );
      }
      readUrl = req.url;
      return http.Response.bytes(Uint8List.fromList([1]), 200);
    });
    final spots =
        await fetchHostedSpots('https://packs.example/', client: client);
    await spots.single.source.read('manifest.json');
    expect(readUrl.toString(), 'https://packs.example/scen/spot/manifest.json');
  });

  test('HttpPackSource reads a chunk from base/relPath, throws on non-200',
      () async {
    final client = MockClient((req) async {
      if (req.url.toString() ==
          'https://packs.example/srp_late_v_bb/7s5s2s_deep/flop.bin.gz') {
        return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
      }
      return http.Response('missing', 404);
    });
    final src = HttpPackSource(
        'https://packs.example/srp_late_v_bb/7s5s2s_deep',
        client: client);
    expect(await src.read('flop.bin.gz'), [1, 2, 3]);
    expect(() => src.read('turn/Ah.bin.gz'), throwsStateError);
  });

  // ── v2 two-level discovery (HostedSpotDiscovery) ──────────────────────────

  String catalogJson() => jsonEncode({
        'version': 2,
        'scenarios': [
          {'key': '3bp_bb_v_btn', 'spots': 2, 'index': 'index/3bp_bb_v_btn.json'},
          {'key': 'srp_late_v_bb', 'spots': 3, 'index': 'index/srp_late_v_bb.json'},
        ],
      });

  test('catalog() parses catalog.json into scenario summaries', () async {
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://packs.example/catalog.json');
      return http.Response(catalogJson(), 200);
    });
    final d = HostedSpotDiscovery('https://packs.example/', client: client);
    final cat = await d.catalog();
    expect([for (final s in cat) s.key], ['3bp_bb_v_btn', 'srp_late_v_bb']);
    expect([for (final s in cat) s.spotCount], [2, 3]);
  });

  test('scenarioSpots() fetches the per-scenario index, sorted + normalized',
      () async {
    Uri? readUrl;
    final client = MockClient((req) async {
      final url = req.url.toString();
      if (url.endsWith('catalog.json')) {
        return http.Response(catalogJson(), 200);
      }
      if (url == 'https://packs.example/index/srp_late_v_bb.json') {
        return http.Response(
          jsonEncode({
            'version': 2,
            'scenario': 'srp_late_v_bb',
            'spots': [
              // Deliberately out of order + a stray-slash path + a bad row.
              {'flop': 'Ks 9h 4c', 'spr': 'medium', 'path': '/srp_late_v_bb/Ks9h4c_medium/'},
              {'flop': '7s 5s 2s', 'spr': 'deep', 'path': 'srp_late_v_bb/7s5s2s_deep'},
              {'flop': 'no spr'},
            ]
          }),
          200,
        );
      }
      readUrl = req.url;
      return http.Response.bytes(Uint8List.fromList([1]), 200);
    });
    final d = HostedSpotDiscovery('https://packs.example', client: client);
    await d.catalog();
    final spots = await d.scenarioSpots('srp_late_v_bb');
    expect([for (final s in spots) s.flop], ['7s 5s 2s', 'Ks 9h 4c']); // sorted
    expect(spots.first.scenario, 'srp_late_v_bb');
    await spots.last.source.read('manifest.json');
    expect(readUrl.toString(),
        'https://packs.example/srp_late_v_bb/Ks9h4c_medium/manifest.json');
  });

  test('no catalog → legacy index.json fallback, zero extra HTTP afterwards',
      () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      final url = req.url.toString();
      if (url.endsWith('catalog.json')) return http.Response('nope', 404);
      if (url.endsWith('index.json')) {
        return http.Response(
          jsonEncode({
            'version': 1,
            'spots': [
              {'scenario': 'b_scen', 'flop': 'Ks 9h 4c', 'spr': 'medium', 'path': 'b_scen/x'},
              {'scenario': 'a_scen', 'flop': '7s 5s 2s', 'spr': 'deep', 'path': 'a_scen/y'},
            ]
          }),
          200,
        );
      }
      return http.Response('missing', 404);
    });
    final d = HostedSpotDiscovery('https://packs.example', client: client);
    final cat = await d.catalog();
    expect([for (final s in cat) s.key], ['a_scen', 'b_scen']);
    final after = requests; // catalog.json + index.json
    expect(await d.scenarioSpots('a_scen'), hasLength(1));
    expect(await d.scenarioSpots('b_scen'), hasLength(1));
    expect(requests, after, reason: 'legacy preload must answer from memory');
  });

  test('catalog + legacy both failing → [] (never throws)', () async {
    final err = MockClient((req) async => http.Response('nope', 404));
    final d = HostedSpotDiscovery('https://packs.example', client: err);
    expect(await d.catalog(), isEmpty);

    final junk = MockClient((req) async => http.Response('not json {{{', 200));
    final d2 = HostedSpotDiscovery('https://packs.example', client: junk);
    expect(await d2.catalog(), isEmpty);
  });

  test('a failed per-scenario index fetch THROWS (distinguishable from empty)',
      () async {
    final client = MockClient((req) async {
      if (req.url.toString().endsWith('catalog.json')) {
        return http.Response(catalogJson(), 200);
      }
      return http.Response('missing', 404);
    });
    final d = HostedSpotDiscovery('https://packs.example', client: client);
    await d.catalog();
    expect(() => d.scenarioSpots('srp_late_v_bb'), throwsStateError);
  });
}
