// GTO Explorer — generate the discovery indexes for the hosted packs.
//
// Scans a local packs root and writes the v2 two-level layout the client
// fetches lazily (lib/explorer/http_packs.dart HostedSpotDiscovery):
//   <root>/catalog.json          { version: 2, scenarios: [{key, spots, index}] }
//   <root>/index/<scenario>.json { version: 2, scenario, spots: [{flop, spr, path}] }
// plus the legacy flat <root>/index.json (v1, all spots — old shipped clients
// still fetch it; opt out with --no-legacy, which also DELETES a stale copy so
// the bulk upload can't ship an outdated one).
//
// The catalog and the legacy index are ALWAYS built from the FULL scan — a
// staged single-scenario run must never delist scenarios already hosted.
// [onlyScenario] only scopes which per-scenario index files are (re)written.
//
// Mirrors lib/explorer scanLocalPacks: accepts BOTH the nested
// `<root>/<scenario>/<spotId>/manifest.json` layout AND the flat
// `<root>/<spotId>/manifest.json` layout, validates each manifest through
// PackManifest.fromJson (so a truncated/malformed spot is skipped, not listed
// as a dead spot), tolerates unlistable dirs, and sorts with the shared key.
//
// Run:  dart run tool/explorer/gen_pack_index.dart [packsRoot] [onlyScenario] [--no-legacy]
//   packsRoot defaults to ~/tlpacks; onlyScenario limits the per-scenario
//   index rewrite to one scenario for a staged upload.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/explorer/pack_manifest.dart';
import 'package:tablelab/explorer/pack_source.dart' show spotSortKey;

void main(List<String> args) {
  final noLegacy = args.contains('--no-legacy');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  final root = positional.isNotEmpty ? positional[0] : '$home/tlpacks';
  final onlyScenario = positional.length > 1 ? positional[1] : null;

  final dir = Directory(root);
  if (!dir.existsSync()) {
    stderr.writeln('packs root not found: $root');
    exit(1);
  }

  final spots = <Map<String, String>>[];
  var skipped = 0;

  String segName(Directory d) =>
      d.uri.pathSegments.where((s) => s.isNotEmpty).last;

  List<Directory> subdirs(Directory d) {
    try {
      return d.listSync().whereType<Directory>().toList();
    } catch (_) {
      return const []; // unlistable (permissions) — skip, not fatal
    }
  }

  void tryAdd(Directory spotDir, String relPath) {
    final mf = File('${spotDir.path}/manifest.json');
    if (!mf.existsSync()) return;
    try {
      final m = PackManifest.fromJson(
          jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>);
      spots.add({
        'scenario': m.scenario,
        'flop': m.flop,
        'spr': m.spr,
        'path': relPath, // relative to the packs base URL
      });
    } catch (_) {
      skipped++; // malformed/incomplete manifest — skip, keep going
    }
  }

  for (final l1 in subdirs(dir)) {
    final l1Name = segName(l1);
    tryAdd(l1, l1Name); // flat layout: <root>/<spotId>
    for (final l2 in subdirs(l1)) {
      tryAdd(l2, '$l1Name/${segName(l2)}'); // nested: <root>/<scenario>/<spotId>
    }
  }

  spots.sort((a, b) => spotSortKey(a['scenario']!, a['flop']!, a['spr']!)
      .compareTo(spotSortKey(b['scenario']!, b['flop']!, b['spr']!)));

  final byScenario = <String, List<Map<String, String>>>{};
  for (final s in spots) {
    (byScenario[s['scenario']!] ??= []).add(s); // keys land sorted (spots are)
  }
  if (onlyScenario != null && !byScenario.containsKey(onlyScenario)) {
    stderr.writeln('scenario not found in scan: $onlyScenario');
    exit(1);
  }

  const enc = JsonEncoder.withIndent('  ');
  final written = <String>[];

  // Per-scenario indexes (v2) — scoped by onlyScenario for a staged upload.
  Directory('$root/index').createSync(recursive: true);
  for (final e in byScenario.entries) {
    if (onlyScenario != null && e.key != onlyScenario) continue;
    final f = File('$root/index/${e.key}.json');
    f.writeAsStringSync(enc.convert({
      'version': 2,
      'scenario': e.key,
      'spots': [
        for (final s in e.value)
          {'flop': s['flop'], 'spr': s['spr'], 'path': s['path']},
      ],
    }));
    written.add('index/${e.key}.json (${e.value.length} spots)');
  }

  // Catalog (v2) — ALWAYS the full scan, never scoped: a staged run must not
  // delist scenarios already hosted. Upload it LAST (see PACK_HOSTING.md).
  File('$root/catalog.json').writeAsStringSync(enc.convert({
    'version': 2,
    'scenarios': [
      for (final e in byScenario.entries)
        {
          'key': e.key,
          'spots': e.value.length,
          'index': 'index/${e.key}.json',
        },
    ],
  }));
  written.add('catalog.json (${byScenario.length} scenarios)');

  // Legacy flat index (v1) — old shipped clients fetch only this. Also full,
  // for the same never-delist reason. Opting out DELETES a stale copy: an
  // outdated legacy index left behind would be re-uploaded by the bulk rclone
  // and served to old clients.
  final legacy = File('$root/index.json');
  if (!noLegacy) {
    legacy.writeAsStringSync(enc.convert({'version': 1, 'spots': spots}));
    written.add('index.json (legacy, ${spots.length} spots)');
  } else if (legacy.existsSync()) {
    legacy.deleteSync();
    written.add('index.json (legacy) deleted (--no-legacy)');
  }

  stdout.writeln('wrote under $root:');
  for (final w in written) {
    stdout.writeln('  $w');
  }
  if (skipped > 0) {
    stdout.writeln('  $skipped spots skipped (malformed manifest)');
  }
  byScenario.forEach((k, v) => stdout.writeln('    $k: ${v.length}'));
}
