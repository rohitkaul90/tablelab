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
}
