// GTO Explorer — Phase 0 SPIKE driver (design: launch/GTO_EXPLORER.md §6).
//
// Solves ONE BTN-vs-BB grid spot locally with the faithful 'river' bet profile
// (dump_rounds 3 — the shipped-library config), then generates an explorer pack
// from the dump and prints the measurements that gate the explorer's downstream
// decisions:
//   1. EV coverage — do `ev`/`ev_passive` populate at every action node?
//      (The solver's EV patch was built for hero-node reads; the explorer needs
//      all nodes. <100% is a CRITICAL finding → solver-patch work before the
//      pack fleet, not a silent workaround.)
//   2. Real chunk sizes (raw + gz) per street → hosting budget + box scratch.
//   3. Pack-gen wall time (parse / rank-cache / matrices / equity / encode).
//
// Usage (PowerShell; shallow spot ≈ a few min solve on 8 threads):
//   $env:TLSOLVE_THREADS='8'
//   dart --old_gen_heap_size=20000 run tool/solver/pack_spike.dart `
//     <outDir> [flop='Ks 9h 4c'] [sprName='shallow']
// The raised heap is for the river-profile dump's jsonDecode (mandatory on
// river dumps — see VCPU_RUNBOOK.md); 20 GB is ample for shallow/medium local.

import 'dart:convert';
import 'dart:io';

import 'explorer_pack.dart';
import 'freq_grid.dart'
    show flopInts, gridSpot, kScenario, kSprReps, scenarioRanges;
import 'run_solver.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln("usage: pack_spike <outDir> [flop='Ks 9h 4c'] [sprName]");
    exit(64);
  }
  final outDir = args[0];
  final flop = args.length > 1 ? args[1] : 'Ks 9h 4c';
  final sprName = args.length > 2 ? args[2] : 'shallow';
  final sprVal = kSprReps[sprName];
  if (sprVal == null) {
    stderr.writeln('unknown sprName "$sprName" (${kSprReps.keys.join('/')})');
    exit(64);
  }

  final ranges = scenarioRanges();
  final spot = gridSpot(flop, sprVal, ranges.ip, ranges.oop);
  stdout.writeln('solving $flop @ SPR $sprVal ($sprName), river profile '
      '(dump_rounds 3), pot ${spot.pot} eff ${spot.effStack} …');

  // forceJsonDump: this tool jsonDecodes the dump itself — the JSON tree is a
  // hard requirement regardless of TLSOLVE_DUMP_FMT or its default.
  final ds = await solveToFile(spot,
      dumpRounds: 3, betProfile: 'river', forceJsonDump: true);
  try {
    final dumpBytes = File(ds.dumpPath).lengthSync();
    stdout.writeln('solved in ${(ds.wallMs / 1000).toStringAsFixed(0)}s · expl '
        '${ds.exploitability?.toStringAsFixed(2)}% · dump '
        '${(dumpBytes / (1024 * 1024)).toStringAsFixed(1)} MB on disk');

    final sw = Stopwatch()..start();
    final root =
        jsonDecode(File(ds.dumpPath).readAsStringSync()) as Map<String, dynamic>;
    stdout.writeln('parsed dump in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');

    // Quick pre-probe before the full walk: is `ev` present at the root?
    stdout.writeln('root ev present: ${root['ev'] != null} · '
        'root ev_passive present: ${root['ev_passive'] != null}');

    final packDir = '$outDir/${flop.replaceAll(' ', '')}_$sprName';
    final total = Stopwatch()..start();
    // Scenario stamp MUST follow TLSOLVE_SCENARIO like the ranges do — a
    // hardcoded key would label a 3-bet-pot pack as single-raised in the
    // explorer.
    final r = generatePack(root,
        board: flopInts(flop),
        pot0: spot.pot.toDouble(),
        effStack: spot.effStack.toDouble(),
        scenario: kScenario,
        sprName: sprName,
        outDir: packDir);
    total.stop();
    printPackReport(r.manifest, r.stats);
    stdout.writeln('pack-gen total ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
        '→ $packDir');
  } finally {
    ds.cleanup();
  }
}
