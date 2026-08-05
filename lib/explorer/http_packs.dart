// GTO Explorer — hosted (HTTP) pack source + discovery. Cross-platform (web +
// mobile, via package:http), so it — unlike the dart:io local scan — works in
// prod. Packs live behind a public base URL (Cloudflare R2).
//
// Discovery is TWO-LEVEL (v2): a tiny `catalog.json` lists the scenarios, and
// each scenario's spots load on demand from `index/<scenario>.json` — a
// 26k-spot fleet never rides one multi-MB index fetch. A host still serving
// only the legacy flat `index.json` (v1) is handled transparently: the whole
// index is fetched once and grouped in memory, so per-scenario reads are then
// instant. Index decoding goes through compute() — a real isolate on
// mobile/desktop, but SYNCHRONOUS on web, where a big legacy index still
// decodes on the UI thread (the v2 lazy path exists precisely to keep those
// payloads small). Catalog failures are tolerated (the explorer just shows no
// spots → Study tab stays hidden) — never fatal; per-scenario fetch failures
// THROW so the UI can offer a retry.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'pack_source.dart';

/// One shared client so chunk fetches reuse connections (BrowserClient on web,
/// pooled IOClient on mobile). Long-lived for the app's lifetime.
final http.Client _shared = http.Client();

/// Bound every request so a stalled host can't wedge Study discovery in a
/// permanent spinner (the local source could never hang; the hosted one can).
/// Generous for pack chunks (<100 KB), but note it also bounds the index
/// fetches — including the multi-MB LEGACY index on the fallback path, which
/// a slow connection can genuinely exceed (acceptable: that path only serves
/// pre-v2 hosts, and a timeout degrades to the empty-catalog state).
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

String _stripTrailingSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;

/// Strip stray leading/trailing slashes so the join is always single-slash
/// ('$root/$path' + '$base/$relPath') — a trailing slash would make a `//`
/// that S3/R2 reads as a different, missing key.
String _cleanPath(String path) => path.replaceAll(RegExp(r'^/+|/+$'), '');

/// One row of a decoded spot index — a plain record so it is compute()-sendable
/// (a [PackSource]/http.Client is not; the [ExplorerSpotRef]s are built back on
/// the main isolate).
typedef SpotIndexRow = ({String scenario, String flop, String spr, String path});

/// Decode index bytes (`{…, spots: [{scenario?, flop, spr, path}]}`) into rows.
/// Top-level so a big index decodes inside compute(). [fallbackScenario] fills
/// rows that omit `scenario` (the v2 per-scenario index shape); rows missing a
/// required field are skipped. Throws on non-JSON bytes.
List<SpotIndexRow> decodeSpotIndexRows(
    (Uint8List, String?) bytesAndScenario) {
  final (bytes, fallbackScenario) = bytesAndScenario;
  final data = jsonDecode(utf8.decode(bytes));
  if (data is! Map || data['spots'] is! List) {
    throw const FormatException('spot index: not a {spots: […]} object');
  }
  final out = <SpotIndexRow>[];
  for (final s in data['spots'] as List) {
    if (s is! Map) continue;
    final scenario = s['scenario']?.toString() ?? fallbackScenario;
    final flop = s['flop']?.toString();
    final spr = s['spr']?.toString();
    final path = s['path']?.toString();
    if (scenario == null || flop == null || spr == null || path == null) {
      continue;
    }
    out.add((scenario: scenario, flop: flop, spr: spr, path: path));
  }
  return out;
}

/// Discover browsable spots from a hosted LEGACY index at `<baseUrl>/index.json`
/// (`{version: 1, spots: [{scenario, flop, spr, path}]}`). Each spot reads
/// through an [HttpPackSource] rooted at `<baseUrl>/<path>`. Returns [] on any
/// network or parse failure — the explorer degrades to "no spots", never
/// throws. Kept as the v1 parser [HostedSpotDiscovery] falls back to.
Future<List<ExplorerSpotRef>> fetchHostedSpots(String baseUrl,
    {http.Client? client}) async {
  final c = client ?? _shared;
  final root = _stripTrailingSlash(baseUrl);
  try {
    final res =
        await c.get(Uri.parse('$root/index.json')).timeout(_httpTimeout);
    if (res.statusCode != 200) return const [];
    // The full-fleet legacy index is multi-MB — decode off the UI isolate.
    final rows = await compute(decodeSpotIndexRows, (res.bodyBytes, null));
    final out = [
      for (final r in rows)
        ExplorerSpotRef(
          scenario: r.scenario,
          flop: r.flop,
          spr: r.spr,
          source: HttpPackSource('$root/${_cleanPath(r.path)}', client: client),
        ),
    ];
    out.sort((a, b) => spotSortKey(a.scenario, a.flop, a.spr)
        .compareTo(spotSortKey(b.scenario, b.flop, b.spr)));
    return out;
  } catch (_) {
    return const [];
  }
}

/// Hosted two-level discovery: `catalog.json` → lazy `index/<scenario>.json`.
/// Falls back to the legacy flat `index.json` when the catalog is absent (an
/// old hosted layout), preloading every scenario in that one fetch.
class HostedSpotDiscovery implements SpotDiscovery {
  final String _root;
  final http.Client? _clientOverride;
  http.Client get _client => _clientOverride ?? _shared;

  HostedSpotDiscovery(String baseUrl, {http.Client? client})
      : _root = _stripTrailingSlash(baseUrl),
        _clientOverride = client;

  /// Per-scenario index paths from the catalog (relative to the base URL).
  final Map<String, String> _indexPaths = {};

  /// Legacy-fallback preload: scenario → sorted spots, filled by ONE
  /// index.json fetch; scenarioSpots then answers from memory (zero HTTP).
  Map<String, List<ExplorerSpotRef>>? _legacy;

  @override
  Future<List<ScenarioSummary>> catalog() async {
    try {
      final res = await _client
          .get(Uri.parse('$_root/catalog.json'))
          .timeout(_httpTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['scenarios'] is List) {
          final out = <ScenarioSummary>[];
          for (final s in data['scenarios'] as List) {
            if (s is! Map) continue;
            final key = s['key']?.toString();
            if (key == null) continue;
            final count = s['spots'];
            _indexPaths[key] = _cleanPath(
                s['index']?.toString() ?? 'index/$key.json');
            out.add(ScenarioSummary(
                key: key, spotCount: count is int ? count : 0));
          }
          // Sort by key even though the generator writes sorted — the
          // auto-selected default scenario must not depend on file order
          // (the spotSortKey rationale, one level up).
          out.sort((a, b) => a.key.compareTo(b.key));
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {
      // Fall through to the legacy index.
    }
    // No/bad catalog — an old hosted layout. One legacy fetch preloads all.
    final spots = await fetchHostedSpots(_root, client: _clientOverride);
    if (spots.isEmpty) return const [];
    final grouped = <String, List<ExplorerSpotRef>>{};
    for (final s in spots) {
      (grouped[s.scenario] ??= []).add(s); // fetchHostedSpots already sorted
    }
    _legacy = grouped;
    return [
      for (final e in grouped.entries)
        ScenarioSummary(key: e.key, spotCount: e.value.length),
    ]..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  Future<List<ExplorerSpotRef>> scenarioSpots(String key) async {
    final preloaded = _legacy?[key];
    if (preloaded != null) return preloaded;
    if (_legacy != null) {
      throw StateError('scenario not in the legacy index: $key');
    }
    final path = _indexPaths[key] ?? 'index/$key.json';
    final res =
        await _client.get(Uri.parse('$_root/$path')).timeout(_httpTimeout);
    if (res.statusCode != 200) {
      throw StateError('scenario index fetch ${res.statusCode}: $_root/$path');
    }
    // A dense scenario's index is large — decode off the UI isolate; the refs
    // (which carry a non-sendable http source) are built back here.
    final rows = await compute(decodeSpotIndexRows, (res.bodyBytes, key));
    final out = [
      for (final r in rows)
        if (r.scenario == key)
          ExplorerSpotRef(
            scenario: r.scenario,
            flop: r.flop,
            spr: r.spr,
            source: HttpPackSource('$_root/${_cleanPath(r.path)}',
                client: _clientOverride),
          ),
    ];
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }
}
