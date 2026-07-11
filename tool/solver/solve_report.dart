// Bulk-campaign cost/progress rollup (full-density prep).
//
// Streams the per-scenario checkpoint shards LINE BY LINE (never loads the
// ~500 MB+ monolith — this must stay usable on the operator machine at any
// campaign size) and prints, per scenario: solved-spot count, per-SPR-bucket
// counts, total solve wall, claimed vCPU-hours (wall × TLSOLVE_THREADS), and
// dollars at a supplied spot rate. This is the per-stage guardrail instrument:
// verify $/spot ≈ the calibration's $0.033 before approving the next slice.
//
//   dart run tool/solver/solve_report.dart                # all shards
//   dart run tool/solver/solve_report.dart --rate 0.022   # $/vCPU-h → $ column
//   dart run tool/solver/solve_report.dart --threads 8    # claim width (default 8)
//
// Reads tool/solver/freq_grid_results.*.jsonl only. The monolith (pre-campaign
// spots) is deliberately excluded: this reports THE CAMPAIGN's spend, and the
// monolith is frozen during it.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  double? rate;
  final rateIdx = args.indexOf('--rate');
  if (rateIdx >= 0 && rateIdx + 1 < args.length) {
    rate = double.tryParse(args[rateIdx + 1]);
  }
  final thIdx = args.indexOf('--threads');
  final threads = (thIdx >= 0 && thIdx + 1 < args.length
          ? int.tryParse(args[thIdx + 1])
          : null) ??
      8;

  final dir = Directory('tool/solver');
  // Shard naming must match freq_grid.dart's _shardPath()
  // ('freq_grid_results.<scenario>.jsonl') — if that convention ever changes,
  // change this filter with it.
  final shards = dir
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'freq_grid_results\..+\.jsonl$')
          .hasMatch(f.uri.pathSegments.last))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (shards.isEmpty) {
    stdout.writeln('no freq_grid_results.*.jsonl shards found — nothing to '
        'report (the monolith is deliberately not read).');
    return;
  }

  var grandSpots = 0;
  var grandWallMs = 0;
  for (final shard in shards) {
    final name = shard.uri.pathSegments.last;
    final bySpr = <String, int>{};
    final seen = <String>{};
    var spots = 0, wallMs = 0, badLines = 0, dupLines = 0;
    var maxExpl = 0.0;
    // One JSON object per line: {"key": ..., "entry": {spot entry}} — the
    // _appendResult format. Streamed (openRead + LineSplitter), never loaded
    // whole: a late-campaign shard is multi-GB. Torn trailing lines (reclaim
    // mid-append) are skipped, like the grid's loader does.
    final lines = shard
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> row;
      try {
        row = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        badLines++;
        continue;
      }
      final v = row['entry'];
      if (v is! Map<String, dynamic>) {
        badLines++;
        continue;
      }
      // Duplicate keys are legal in a shard (later-wins fold: re-solves, and
      // the end-of-stage worktree concat-merge). Count UNIQUE spots for
      // progress — but keep every line's wall in the cost total, because a
      // re-solved duplicate was paid for twice. $/spot = total $ ÷ unique,
      // so duplication correctly RAISES the guardrail number.
      wallMs += (v['wall_ms'] as num?)?.toInt() ?? 0;
      final key = row['key'] as String? ?? '';
      if (!seen.add(key)) {
        dupLines++;
        continue;
      }
      spots++;
      bySpr.update(v['spr'] as String? ?? '?', (n) => n + 1,
          ifAbsent: () => 1);
      final e = (v['exploitability'] as num?)?.toDouble();
      if (e != null && e > maxExpl) maxExpl = e;
    }
    grandSpots += spots;
    grandWallMs += wallMs;
    final vcpuH = wallMs / 3600e3 * threads;
    final sprStr =
        (bySpr.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key} ${e.value}')
            .join(', ');
    stdout.writeln('$name: $spots spots ($sprStr) · solve wall '
        '${(wallMs / 3600e3).toStringAsFixed(1)} h · ~${vcpuH.toStringAsFixed(0)} '
        'claimed vCPU-h · max expl ${maxExpl.toStringAsFixed(2)}%'
        '${rate != null ? ' · ~\$${(vcpuH * rate).toStringAsFixed(0)}' : ''}'
        '${dupLines > 0 ? ' · ⚠ $dupLines duplicate key(s) (re-solved/merged '
            'twice — wall counted, spot not)' : ''}'
        '${badLines > 0 ? ' · ⚠ $badLines unparseable line(s)' : ''}');
  }
  final gVcpuH = grandWallMs / 3600e3 * threads;
  stdout.writeln('TOTAL: $grandSpots spots · ~${gVcpuH.toStringAsFixed(0)} '
      'claimed vCPU-h'
      '${rate != null ? ' · ~\$${(gVcpuH * rate).toStringAsFixed(0)} '
          '(~\$${grandSpots == 0 ? '0' : (gVcpuH * rate / grandSpots).toStringAsFixed(3)}/spot)' : ''}');
}
