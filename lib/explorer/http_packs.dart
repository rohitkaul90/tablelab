// GTO Explorer — hosted (HTTP) pack source + discovery. Cross-platform (web +
// mobile, via package:http), so it — unlike the dart:io local scan — works in
// prod. Packs live behind a public base URL (Cloudflare R2); discovery fetches
// ONE index.json listing every spot, then each spot reads its own chunks over
// HTTP. Failures are tolerated (the explorer just shows no spots → Study tab
// stays hidden) — never fatal.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'pack_source.dart';

/// One shared client so chunk fetches reuse connections (BrowserClient on web,
/// pooled IOClient on mobile). Long-lived for the app's lifetime.
final http.Client _shared = http.Client();

/// Bound every request so a stalled host can't wedge Study discovery in a
/// permanent spinner (the local source could never hang; the hosted one can).
/// Generous — pack chunks are small (<100 KB), so this only ever trips on a
/// genuinely stalled connection, not a slow-but-progressing download.
const Duration _httpTimeout = Duration(seconds: 20);

/// Reads a spot's pack files from a base URL: `<base>/manifest.json`,
/// `<base>/flop.bin.gz`, `<base>/turn/Ah.bin.gz`, … The chunk paths come from
/// the manifest (relative), exactly as the local source uses them.
class HttpPackSource implements PackSource {
  /// The spot's root URL (no trailing slash), e.g.
  /// `https://packs.tablelab.app/srp_late_v_bb/7s5s2s_deep`.
  final String base;
  final http.Client _client;
  HttpPackSource(this.base, {http.Client? client})
      : _client = client ?? _shared;

  @override
  Future<Uint8List> read(String relPath) async {
    final res =
        await _client.get(Uri.parse('$base/$relPath')).timeout(_httpTimeout);
    if (res.statusCode != 200) {
      throw StateError('pack fetch ${res.statusCode}: $base/$relPath');
    }
    return res.bodyBytes;
  }
}

/// Discover browsable spots from a hosted index at `<baseUrl>/index.json`
/// (`{version, spots: [{scenario, flop, spr, path}]}`). Each spot reads through
/// an [HttpPackSource] rooted at `<baseUrl>/<path>`. Returns [] on any network
/// or parse failure — the explorer degrades to "no spots", never throws.
Future<List<ExplorerSpotRef>> fetchHostedSpots(String baseUrl,
    {http.Client? client}) async {
  final c = client ?? _shared;
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  try {
    final res =
        await c.get(Uri.parse('$root/index.json')).timeout(_httpTimeout);
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map || data['spots'] is! List) return const [];
    final out = <ExplorerSpotRef>[];
    for (final s in data['spots'] as List) {
      if (s is! Map) continue;
      final scenario = s['scenario']?.toString();
      final flop = s['flop']?.toString();
      final spr = s['spr']?.toString();
      final path = s['path']?.toString();
      if (scenario == null || flop == null || spr == null || path == null) {
        continue;
      }
      // Strip stray leading/trailing slashes so the join is always single-slash
      // ('$root/$path' + '$base/$relPath') — a trailing slash would make a `//`
      // that S3/R2 reads as a different, missing key.
      final cleanPath = path.replaceAll(RegExp(r'^/+|/+$'), '');
      out.add(ExplorerSpotRef(
        scenario: scenario,
        flop: flop,
        spr: spr,
        source: HttpPackSource('$root/$cleanPath', client: client),
      ));
    }
    out.sort((a, b) => spotSortKey(a.scenario, a.flop, a.spr)
        .compareTo(spotSortKey(b.scenario, b.flop, b.spr)));
    return out;
  } catch (_) {
    return const [];
  }
}
