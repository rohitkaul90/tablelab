// GTO Explorer — generate index.json for the hosted packs.
//
// Scans a local packs root (`<root>/<scenario>/<spotId>/manifest.json`, the
// vcpu-solve.ps1 -PackDest / ~/tlpacks layout), reads each manifest for its
// labels, and writes `<root>/index.json` = { version, spots: [{scenario, flop,
// spr, path}] }. That file uploads with the packs; the app fetches it to
// discover spots (lib/explorer/http_packs.dart fetchHostedSpots).
//
// Run:  dart run tool/explorer/gen_pack_index.dart [packsRoot]
//   packsRoot defaults to ~/tlpacks. Optional 2nd arg filters to ONE scenario
//   (for a staged first-scenario upload).

import 'dart:convert';
import 'dart:io';

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
  for (final scenDir in dir.listSync().whereType<Directory>()) {
    final scenName = scenDir.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last; // dir name
    if (onlyScenario != null && scenName != onlyScenario) continue;
    for (final spotDir in scenDir.listSync().whereType<Directory>()) {
      final mf = File('${spotDir.path}/manifest.json');
      if (!mf.existsSync()) continue;
      try {
        final m = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
        final spotName =
            spotDir.uri.pathSegments.where((s) => s.isNotEmpty).last;
        spots.add({
          'scenario': m['scenario']?.toString() ?? scenName,
          'flop': m['flop']?.toString() ?? '?',
          'spr': m['spr']?.toString() ?? '?',
          'path': '$scenName/$spotName', // relative to the packs base URL
        });
      } catch (_) {
        skipped++; // malformed manifest — skip, keep going
      }
    }
  }

  spots.sort((a, b) => ('${a['scenario']}|${a['flop']}|${a['spr']}')
      .compareTo('${b['scenario']}|${b['flop']}|${b['spr']}'));

  final out = File('$root/index.json');
  out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'version': 1, 'spots': spots}));
  stdout.writeln('wrote ${out.path}');
  stdout.writeln('  ${spots.length} spots'
      '${onlyScenario != null ? ' (scenario=$onlyScenario)' : ''}'
      '${skipped > 0 ? ', $skipped skipped' : ''}');
  final byScen = <String, int>{};
  for (final s in spots) {
    byScen[s['scenario']!] = (byScen[s['scenario']] ?? 0) + 1;
  }
  byScen.forEach((k, v) => stdout.writeln('    $k: $v'));
}
