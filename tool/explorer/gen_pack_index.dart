// GTO Explorer — generate index.json for the hosted packs.
//
// Scans a local packs root and writes `<root>/index.json` = { version, spots:
// [{scenario, flop, spr, path}] }. That file uploads with the packs; the app
// fetches it to discover spots (lib/explorer/http_packs.dart fetchHostedSpots).
//
// Mirrors lib/explorer scanLocalPacks: accepts BOTH the nested
// `<root>/<scenario>/<spotId>/manifest.json` layout AND the flat
// `<root>/<spotId>/manifest.json` layout, validates each manifest through
// PackManifest.fromJson (so a truncated/malformed spot is skipped, not listed
// as a dead spot), tolerates unlistable dirs, and sorts with the shared key.
//
// Run:  dart run tool/explorer/gen_pack_index.dart [packsRoot] [onlyScenario]
//   packsRoot defaults to ~/tlpacks; onlyScenario filters to one scenario for a
//   staged first-scenario upload.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/explorer/pack_manifest.dart';
import 'package:tablelab/explorer/pack_source.dart' show spotSortKey;

void main(List<String> args) {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  final root = args.isNotEmpty ? args[0] : '$home/tlpacks';
  final onlyScenario = args.length > 1 ? args[1] : null;

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

  final selected = onlyScenario == null
      ? spots
      : spots.where((s) => s['scenario'] == onlyScenario).toList();
  selected.sort((a, b) => spotSortKey(a['scenario']!, a['flop']!, a['spr']!)
      .compareTo(spotSortKey(b['scenario']!, b['flop']!, b['spr']!)));

  final out = File('$root/index.json');
  out.writeAsStringSync(const JsonEncoder.withIndent('  ')
      .convert({'version': 1, 'spots': selected}));
  stdout.writeln('wrote ${out.path}');
  stdout.writeln('  ${selected.length} spots'
      '${onlyScenario != null ? ' (scenario=$onlyScenario)' : ''}'
      '${skipped > 0 ? ', $skipped skipped (malformed manifest)' : ''}');
  final byScen = <String, int>{};
  for (final s in selected) {
    byScen[s['scenario']!] = (byScen[s['scenario']] ?? 0) + 1;
  }
  byScen.forEach((k, v) => stdout.writeln('    $k: $v'));
}
