// GTO Explorer — dart:io pack source (desktop/mobile dev against a local
// packs directory, e.g. the vcpu-solve.ps1 -PackDest pull). Reached via the
// conditional export in pack_source.dart; web builds get local_packs_stub.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pack_manifest.dart';
import 'pack_source.dart';

/// Default local packs root: `~/tlpacks` (vcpu-solve.ps1 -PackDest default) —
/// so a pulled pack fleet is auto-discovered in dev. Overridable with
/// --dart-define=TLPACKS_DIR=…; null when no home dir is resolvable.
String? defaultPacksRoot() {
  const override = String.fromEnvironment('TLPACKS_DIR');
  if (override.isNotEmpty) return override;
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'];
  return home == null ? null : '$home/tlpacks';
}

class LocalDirPackSource implements PackSource {
  /// The spot's root directory (the one containing manifest.json).
  final String root;
  LocalDirPackSource(this.root);

  @override
  Future<Uint8List> read(String relPath) =>
      File('$root/$relPath').readAsBytes();
}

/// Scan a local packs root for spots. Accepts both layouts:
/// `<root>/<scenario>/<spotId>/manifest.json` (the generator/puller layout)
/// and `<root>/<spotId>/manifest.json` (e.g. the Phase-0 spike output).
/// Labels come from each manifest. Unreadable spots are skipped, not fatal.
Future<List<ExplorerSpotRef>> scanLocalPacks(String root) async {
  final dir = Directory(root);
  if (!await dir.exists()) return const [];
  final out = <ExplorerSpotRef>[];
  Future<void> tryAdd(Directory spotDir) async {
    final mf = File('${spotDir.path}/manifest.json');
    if (!await mf.exists()) return;
    try {
      final m = PackManifest.fromJson(
          jsonDecode(await mf.readAsString()) as Map<String, dynamic>);
      out.add(ExplorerSpotRef(
        scenario: m.scenario,
        flop: m.flop,
        spr: m.spr,
        source: LocalDirPackSource(spotDir.path),
      ));
    } catch (_) {
      // Malformed manifest — skip this spot, keep scanning.
    }
  }

  Future<List<Directory>> subdirs(Directory d) async {
    try {
      return [
        await for (final e in d.list())
          if (e is Directory) e
      ];
    } catch (_) {
      return const []; // unlistable dir (permissions) — skip, not fatal
    }
  }

  for (final e in await subdirs(dir)) {
    await tryAdd(e);
    for (final sub in await subdirs(e)) {
      await tryAdd(sub);
    }
  }
  out.sort((a, b) => spotSortKey(a.scenario, a.flop, a.spr)
      .compareTo(spotSortKey(b.scenario, b.flop, b.spr)));
  return out;
}
