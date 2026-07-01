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
// It reads the solver dump, tabulates it (the SAME `tabulateDumpFile` the grid used
// in-isolate), and writes the cell JSON list to an output file — a file, not stdout,
// so a big cell list never has to buffer through Process.run's captured stdout.
//
// Args: <dumpPath> <outPath> <flopNoSpaces e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen>

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';

import 'freq_tabulate.dart';

void main(List<String> args) {
  if (args.length < 6) {
    stderr.writeln('usage: tabulate_one <dumpPath> <outPath> '
        '<flop e.g. Ks9h4c> <pot0> <effStack> <maxBoardLen>');
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
  final cells = tabulateDumpFile(dumpPath,
      board: flop, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
  File(outPath).writeAsStringSync(jsonEncode([for (final c in cells) c.toJson()]));
}
