// GTO Explorer — where pack bytes come from.
//
// The client reads a pack through a [PackSource] (paths relative to one spot's
// root: 'manifest.json', 'flop.bin.gz', 'turn/Ah.bin.gz', …). Sources:
//  - LocalDirPackSource + scanLocalPacks (dart:io — desktop/mobile dev against
//    a pulled packs directory; stubbed out on web via conditional export).
//  - HttpPackSource (http_packs.dart) — the hosted source, live on Cloudflare
//    R2 (packs.tablelab.app); the client is source-agnostic.

import 'dart:typed_data';

export 'local_packs_stub.dart' if (dart.library.io) 'local_packs_io.dart';

abstract class PackSource {
  /// Read a file within the spot's pack (throws on missing).
  Future<Uint8List> read(String relPath);
}

/// One browsable spot: labels for the picker + the source to read it from.
///
/// Equality is by [id] (VALUE, not object identity) — with lazy per-scenario
/// discovery the same spot can be re-materialized by separate index fetches,
/// and the staleness checks (selectSpot's post-await guard, the root-equity
/// memo, the client LRU key) must treat those as the same spot.
class ExplorerSpotRef {
  final String scenario;
  final String flop; // 'Ks 9h 4c'
  final String spr; // regime name
  final PackSource source;

  /// Stable identity — defaults to the shared sort key, so two refs to the
  /// same {scenario, flop, spr} compare equal regardless of source instance.
  final String id;

  ExplorerSpotRef({
    required this.scenario,
    required this.flop,
    required this.spr,
    required this.source,
    String? id,
  }) : id = id ?? spotSortKey(scenario, flop, spr);

  String get label => '$flop · $spr';

  /// Excluding [source] from equality is sound because ONE discovery serves a
  /// session (init() settles on a single [SpotDiscovery]) — every ref minted
  /// for an id reads from the same base URL/directory, so two equal refs are
  /// interchangeable. If refs ever mix discoveries in one session, revisit.
  @override
  bool operator ==(Object other) => other is ExplorerSpotRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One catalog row: a scenario key + how many spots its index lists. The
/// catalog is tiny (a handful of rows) — full spot lists load lazily per
/// scenario through [SpotDiscovery.scenarioSpots].
class ScenarioSummary {
  final String key;
  final int spotCount;
  const ScenarioSummary({required this.key, required this.spotCount});
}

/// Two-level spot discovery: a cheap catalog of scenarios up front, spot lists
/// on demand — so a 26k-spot fleet never rides one giant index fetch.
abstract class SpotDiscovery {
  /// The scenario catalog. Returns [] on ANY failure, never throws — an empty
  /// catalog just hides the Study tab (the tab-gate contract).
  Future<List<ScenarioSummary>> catalog();

  /// The spots of one scenario, sorted by [spotSortKey]. THROWS on failure —
  /// the caller must be able to tell "index fetch failed" (retryable) from
  /// "scenario genuinely has no spots".
  Future<List<ExplorerSpotRef>> scenarioSpots(String key);
}

/// The stable spot ordering key — ONE definition so the hosted index, the local
/// scan, and the generator all sort identically (init() auto-selects
/// spots.first, so divergent orders would pick different default spots).
String spotSortKey(String scenario, String flop, String spr) =>
    '$scenario|$flop|$spr';
