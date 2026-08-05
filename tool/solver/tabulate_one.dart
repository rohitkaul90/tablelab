// GTO frequency library — standalone per-spot TABULATOR, run as a SEPARATE
// PROCESS by freq_grid.dart's worker.
//
// WHY a process (not an Isolate): the earlier `Isolate.run` tabulation ran every
// concurrent parse inside ONE shared isolate-group heap, so N deep-river dumps
// (~15 GB each) contended on a SINGLE garbage collector and stalled each other —
// measured at ~4.7 effective cores across 10 parses (~2 spots/hr) on a 128-vCPU
// box. A subprocess per spot gives each parse its OWN heap + GC, so `--parallel`
// workers truly parallelize the (single-threaded, GC-heavy) jsonDecode+walk across
// cores. Give this process a big heap for a deep dump:
//   dart --old_gen_heap_size=80000 run tool/solver/tabulate_one.dart …
// (freq_grid passes --old_gen_heap_size from TLSOLVE_TABULATE_HEAP_MB, default 80 GB).
//
// It reads the solver dump, tabulates it (the SAME `tabulateSpot` walk the grid
// used in-isolate), and writes the cell JSON list to an output file — a file, not
// stdout, so a big cell list never has to buffer through Process.run's captured
// stdout.
//
// Args: <dumpPath> <outPath> <flopNoSpaces e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen>
//       [--emit-pack <packOutDir> <scenario> <sprName>]
//
// --emit-pack additionally generates the GTO Explorer pack (explorer_pack.dart)
// from the SAME parsed dump — one heavy jsonDecode, two outputs. This is the hook
// that lets a solve cycle produce library cells AND explorer packs in one pass
// (design: launch/GTO_EXPLORER.md).

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';

import 'dump_codec.dart';
import 'explorer_pack.dart';
import 'freq_tabulate.dart';

void main(List<String> args) {
  if (args.length < 6) {
    stderr.writeln('usage: tabulate_one <dumpPath> <outPath> '
        '<flop e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen> '
        '[--emit-pack <packOutDir> <scenario> <sprName>]');
    exit(64);
  }
  final dumpPath = args[0];
  final outPath = args[1];
  // Flop is passed space-free ("Ks9h4c"); parse two chars at a time (matches the
  // freq_tabulate debug CLI / the grid's flopInts on the space-form).
  final flop = <int>[];
  for (var i = 0; i + 1 < args[2].length; i += 2) {
    final c = parseCard(args[2].substring(i, i + 2));
    if (c >= 0) flop.add(c);
  }
  final pot0 = double.tryParse(args[3]);
  final effStack = double.tryParse(args[4]);
  final maxBoardLen = int.tryParse(args[5]);
  if (flop.length < 3 || pot0 == null || effStack == null || maxBoardLen == null) {
    stderr.writeln('tabulate_one: bad args '
        '(flop=${args[2]} pot0=${args[3]} effStack=${args[4]} maxLen=${args[5]})');
    exit(64);
  }
  final packIdx = args.indexOf('--emit-pack');
  if (packIdx >= 0 && args.length < packIdx + 4) {
    stderr.writeln('tabulate_one: --emit-pack needs <packOutDir> <scenario> '
        '<sprName>');
    exit(64);
  }
  // Dispatch on the dump's magic bytes: a TLSD binary dump (dump_result_bin)
  // decodes via the streaming cursor — a fraction of the JSON path's heap —
  // and goes straight to tabulation. Pack emission (the TLSD pack port,
  // 2026-08-05) runs a SECOND independent streaming pass over the same file:
  // the cursor is single-pass/forward-only, so cells and packs each get their
  // own walk; two decode passes over ~1-2 GB of bytes beat one eager
  // multi-GB typed tree.
  if (looksLikeTlsd(dumpPath)) {
    final cells = tabulateDumpFile(dumpPath,
        board: flop, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
    File(outPath)
        .writeAsStringSync(jsonEncode([for (final c in cells) c.toJson()]));
    if (packIdx >= 0) {
      // Secondary output: a pack failure must never flip the exit code (the
      // grid would discard the successful tabulation + dump) — WARN, exit 0.
      try {
        final dump = readTlsdStreamFile(dumpPath);
        final root = dump.root;
        if (root == null) {
          throw StateError('TLSD dump has an omitted root node');
        }
        // Root is structurally OOP's node; its player index picks which
        // header dict seeds the IP registry (streaming can't peek children).
        final rootPlayer = root.playerIndex == 1 ? 1 : 0;
        final r = generatePackFromView(root,
            board: flop,
            pot0: pot0,
            effStack: effStack,
            scenario: args[packIdx + 2],
            sprName: args[packIdx + 3],
            outDir: args[packIdx + 1],
            maxBoardLen: maxBoardLen,
            ipSeedKeys: dump.dicts[1 - rootPlayer].keys);
        dump.finish();
        printPackReport(r.manifest, r.stats);
      } catch (e) {
        stderr.writeln('WARN tabulate_one: pack emission FAILED (cells are '
            'unaffected and were written): $e');
        stdout.writeln('pack emission FAILED for ${args[packIdx + 1]} — see '
            'stderr; cells unaffected.');
      }
    }
    return;
  }
  // Parse ONCE (the multi-GB decode is the expensive step), then walk twice.
  final root =
      jsonDecode(File(dumpPath).readAsStringSync()) as Map<String, dynamic>;
  final cells = tabulateSpot(root,
      board: flop, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
  File(outPath).writeAsStringSync(jsonEncode([for (final c in cells) c.toJson()]));
  if (packIdx >= 0) {
    // Pack emission is a SECONDARY output: the cells are already written, and
    // a pack failure (e.g. disk-full on the packs volume) must not flip this
    // process's exit code — the grid would then discard the successful
    // tabulation AND delete the dump, losing the whole paid solve for the
    // spot. Warn loudly and exit 0; the operator re-emits packs from a
    // re-solve, the library is unaffected.
    try {
      final r = generatePack(root,
          board: flop,
          pot0: pot0,
          effStack: effStack,
          scenario: args[packIdx + 2],
          sprName: args[packIdx + 3],
          outDir: args[packIdx + 1],
          maxBoardLen: maxBoardLen);
      printPackReport(r.manifest, r.stats);
    } catch (e) {
      stderr.writeln('WARN tabulate_one: pack emission FAILED (cells are '
          'unaffected and were written): $e');
      stdout.writeln('pack emission FAILED for ${args[packIdx + 1]} — see '
          'stderr; cells unaffected.');
    }
  }
}
