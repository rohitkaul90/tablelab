// Calibration batch runner for the TexasSolver bridge.
//
// Solves a balanced set of flop spots and, per {hand-class × position} bucket
// (the keys the EQR table uses), compares the DCE heuristics (realized equity,
// EQR multiplier) against the solver's GTO action + per-action EV. Output: a
// resumable per-spot JSON + a markdown calibration report.
//
//   dart run tool/solver/batch.dart [maxPerBucket=3] [totalCap=24]
//
// Resumable: re-running skips spots already in batch_results.json. Each deep
// solve is ~100-150s, so this is an hours-long BACKGROUND run for a full batch.
// Operator-only (uses the licensed solver locally). See run_solver.dart for the
// TEXASSOLVER_DIR / solver_config.json setup.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';
import 'package:tablelab/models/player_read.dart';

import 'run_solver.dart';
import 'solver_input.dart';

const _fixturesDir = 'tool/eval/fixtures';
const _realHandPath = 'tool/solver/real_hand.json';
const _resultsPath = 'tool/solver/batch_results.json';
const _reportPath = 'tool/solver/batch_report.md';

class Candidate {
  final String id;
  final PokerHand hand;
  final List<PlayerRead> reads;
  Candidate(this.id, this.hand, this.reads);
}

Future<void> main(List<String> args) async {
  final maxPerBucket = args.isNotEmpty ? int.parse(args[0]) : 3;
  final totalCap = args.length > 1 ? int.parse(args[1]) : 24;

  // ── 1. Gather solver-mappable candidates (no-reads only, so the solver's GTO
  //       ranges and the DCE villain model assume the same baseline). ──
  final candidates = <Candidate>[];
  var skippedUnsupported = 0, skippedReads = 0;
  for (final f in Directory(_fixturesDir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final fx = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final reads = _parseReads(fx['reads']);
    if (reads.isNotEmpty) {
      skippedReads++;
      continue; // reads variants are for reads-testing, not EQR calibration
    }
    final hand = PokerHand.fromJson(fx['hand'] as Map<String, dynamic>);
    try {
      SolverSpot.fromHand(hand);
    } on UnsupportedSpot {
      skippedUnsupported++;
      continue;
    } catch (_) {
      skippedUnsupported++;
      continue;
    }
    candidates.add(Candidate(fx['id'] as String, hand, reads));
  }
  // Include the exported real hand, if present.
  final realFile = File(_realHandPath);
  if (realFile.existsSync()) {
    final rj = jsonDecode(realFile.readAsStringSync()) as Map<String, dynamic>;
    final hand = PokerHand.fromJson((rj['hand'] ?? rj) as Map<String, dynamic>);
    try {
      SolverSpot.fromHand(hand);
      candidates.add(Candidate('real:${hand.id}', hand, _parseReads(rj['reads'])));
    } on UnsupportedSpot {/* skip */}
  }
  stdout.writeln('Candidates: ${candidates.length} mappable '
      '(skipped $skippedReads with reads, $skippedUnsupported unsupported).');

  // ── 2. DCE metrics + bucket by {hand-class × position}. ──
  final byBucket = <String, List<_Scored>>{};
  for (final c in candidates) {
    final check = await computeHandEquityCheck(c.hand, reads: c.reads, seed: 1234);
    final flop = check?.streets
        .where((s) => s.street == Street.flop)
        .cast<StreetEquityCheck?>()
        .firstWhere((s) => true, orElse: () => null);
    if (flop == null || flop.realizedHandClass == null || flop.heroInPosition == null) {
      continue; // need a classified flop spot to bucket/calibrate
    }
    final bucket = '${flop.realizedHandClass!.name}/${flop.heroInPosition! ? "IP" : "OOP"}';
    byBucket.putIfAbsent(bucket, () => []).add(_Scored(c, flop));
  }

  // ── 3. Select up to maxPerBucket per bucket (deterministic by id), capped. ──
  final selected = <_Scored>[];
  for (final entry in byBucket.entries) {
    entry.value.sort((a, b) => a.c.id.compareTo(b.c.id));
    selected.addAll(entry.value.take(maxPerBucket));
  }
  selected.sort((a, b) => a.c.id.compareTo(b.c.id));
  final capped = selected.take(totalCap).toList();
  stdout.writeln('Buckets: ${byBucket.keys.length}. Selected ${capped.length} '
      'spots (maxPerBucket=$maxPerBucket, totalCap=$totalCap).');
  if (selected.length > capped.length) {
    stdout.writeln('NOTE: dropped ${selected.length - capped.length} selected '
        'spots to the total cap — raise totalCap to include them.');
  }

  // ── 4. Solve (resumable). ──
  final results = <String, dynamic>{};
  final resultsFile = File(_resultsPath);
  if (resultsFile.existsSync()) {
    results.addAll(jsonDecode(resultsFile.readAsStringSync()) as Map<String, dynamic>);
    stdout.writeln('Resuming: ${results.length} spots already solved.');
  }

  var n = 0;
  for (final s in capped) {
    n++;
    if (results.containsKey(s.c.id)) {
      stdout.writeln('[$n/${capped.length}] ${s.c.id} — cached, skip.');
      continue;
    }
    final spot = SolverSpot.fromHand(s.c.hand);
    stdout.writeln('[$n/${capped.length}] ${s.c.id} (${s.bucket}) solving…');
    SolveResult res;
    try {
      res = await solve(spot);
    } catch (e) {
      stdout.writeln('   ERROR: $e');
      continue;
    }
    results[s.c.id] = _spotResult(s, spot, res);
    resultsFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    final r = results[s.c.id] as Map<String, dynamic>;
    stdout.writeln('   top=${r["gtoTopAction"]}  nodeEV=${r["gtoNodeEv"]}  '
        'EV/pot=${r["evPerPot"]}  gap=${r["evGap"]}  (${res.wallMs ~/ 1000}s)');
  }

  // ── 5. Aggregate → report. ──
  // Re-derive each spot's SolverSpot (cheap, no solve) so the realized-equity
  // formula has C_hero even for spots solved in an earlier run.
  final spotsById = <String, SolverSpot>{};
  for (final s in capped) {
    try {
      spotsById[s.c.id] = SolverSpot.fromHand(s.c.hand);
    } catch (_) {}
  }
  _writeReport(results, byBucket, spotsById, maxPerBucket, totalCap);
  stdout.writeln('\nWrote $_reportPath ($_resultsPath has ${results.length} spots).');
}

class _Scored {
  final Candidate c;
  final StreetEquityCheck flop;
  _Scored(this.c, this.flop);
  String get bucket =>
      '${flop.realizedHandClass!.name}/${flop.heroInPosition! ? "IP" : "OOP"}';
}

Map<String, dynamic> _spotResult(_Scored s, SolverSpot spot, SolveResult res) {
  final raw = s.flop.heroEquity;
  final realized = s.flop.realizedEquity;
  double? nodeEv;
  double? evGap; // best EV minus 2nd-best EV across offered actions
  if (res.evs != null && res.evs!.isNotEmpty) {
    nodeEv = 0;
    for (var i = 0; i < res.probs.length && i < res.evs!.length; i++) {
      nodeEv = nodeEv! + res.probs[i] * res.evs![i];
    }
    final sorted = [...res.evs!]..sort((a, b) => b.compareTo(a));
    if (sorted.length >= 2) evGap = sorted[0] - sorted[1];
  }
  return {
    'id': s.c.id,
    'bucket': s.bucket,
    'handClass': s.flop.realizedHandClass!.name,
    'position': s.flop.heroInPosition! ? 'IP' : 'OOP',
    'spr': s.flop.spr,
    'board': spot.board.join(' '),
    'heroCombo': spot.heroCombo,
    'pot': spot.pot,
    'heroContribution': spot.heroContribution,
    'rawEquity': _r(raw),
    'realizedEquity': _r(realized),
    'dceMultiplier': (realized != null && raw > 0) ? _r(realized / raw) : null,
    'gtoActions': res.actions,
    'gtoProbs': res.probs.map(_r).toList(),
    'gtoEvs': res.evs?.map(_r).toList(),
    'gtoTopAction': res.topAction,
    'gtoNodeEv': _r(nodeEv),
    'passiveEv': _r(res.passiveEv),
    'evPerPot': nodeEv != null ? _r(nodeEv / spot.pot) : null,
    'evGap': _r(evGap),
    'exploitability': res.exploitability,
    'wallSec': res.wallMs ~/ 1000,
  };
}

// Realized equity from solver EV:  R = (EV_GTO + C_hero) / pot ;  EQR = R / rawEq.
// Net-chip EV frame verified by regression (EV/pot ≈ 1.45·e − 0.62). Needs ACTUAL
// C_hero (dead money makes pot > 2·C_hero), supplied via spotsById.
double? _realizedR(Map<String, dynamic> row, Map<String, SolverSpot> spotsById) {
  final ev = row['gtoNodeEv'], pot = row['pot'];
  final c = spotsById[row['id']]?.heroContribution ?? row['heroContribution'];
  if (ev is! num || pot is! num || pot == 0 || c is! num) return null;
  return (ev + c) / pot;
}

double? _eqrEmp(Map<String, dynamic> row, Map<String, SolverSpot> spotsById) {
  final r = _realizedR(row, spotsById);
  final raw = row['rawEquity'];
  if (r == null || raw is! num || raw <= 0) return null;
  return r / raw;
}

// Showdown realization (no fold equity): R_show = (passiveEv + C_hero) / pot.
double? _realizedRShow(Map<String, dynamic> row, Map<String, SolverSpot> spotsById) {
  final ev = row['passiveEv'], pot = row['pot'];
  final c = spotsById[row['id']]?.heroContribution ?? row['heroContribution'];
  if (ev is! num || pot is! num || pot == 0 || c is! num) return null;
  return (ev + c) / pot;
}

double? _eqrShow(Map<String, dynamic> row, Map<String, SolverSpot> spotsById) {
  final r = _realizedRShow(row, spotsById);
  final raw = row['rawEquity'];
  if (r == null || raw is! num || raw <= 0) return null;
  return r / raw;
}

void _writeReport(Map<String, dynamic> results, Map<String, List<_Scored>> byBucket,
    Map<String, SolverSpot> spotsById, int maxPerBucket, int totalCap) {
  final rows = results.values.cast<Map<String, dynamic>>().toList()
    ..sort((a, b) => (a['bucket'] as String).compareTo(b['bucket'] as String));
  for (final r in rows) {
    r['R'] = _r(_realizedR(r, spotsById));
    r['eqrEmp'] = _r(_eqrEmp(r, spotsById));
    r['eqrShow'] = _r(_eqrShow(r, spotsById));
  }
  final b = StringBuffer();
  b.writeln('# TexasSolver calibration batch\n');
  b.writeln('Spots solved: ${rows.length}  ·  maxPerBucket=$maxPerBucket  ·  '
      'totalCap=$totalCap\n');
  b.writeln('**Realized equity:** `R = (EV_GTO + C_hero) / pot`, `EQR_emp = R / rawEq` '
      '(net-chip EV frame, verified by regression; uses each spot\'s actual committed '
      'chips). Compare **EQR_emp** to the DCE multiplier — that is the calibration '
      'target. R>1 = over-realization (wins future bets); R<0 clamped at 0 in reading. '
      'Loose convergence (3-4.5% expl.) → treat as directional, not final values.\n');

  // Per-bucket aggregate.
  final buckets = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    buckets.putIfAbsent(r['bucket'] as String, () => []).add(r);
  }
  b.writeln('## Per-bucket calibration (DCE vs solver)\n');
  b.writeln('EQR_emp = total realization (incl. fold equity); '
      '**EQR_show = showdown realization only (check/call line, NO fold equity) — '
      'the right target for the bluff-catch EQR multiplier.**\n');
  b.writeln('| Bucket (handClass/pos) | n | avg raw eq | **DCE mult** | '
      'EQR_emp (total) | **EQR_show (no-FE)** | avg EV gap |');
  b.writeln('|---|---|---|---|---|---|---|');
  for (final entry in buckets.entries) {
    final v = entry.value;
    String avg(String k) {
      final xs = v.map((r) => r[k]).whereType<num>().toList();
      if (xs.isEmpty) return '–';
      return (xs.reduce((a, b) => a + b) / xs.length).toStringAsFixed(2);
    }
    b.writeln('| ${entry.key} | ${v.length} | ${avg("rawEquity")} | '
        '${avg("dceMultiplier")} | ${avg("eqrEmp")} | ${avg("eqrShow")} | '
        '${avg("evGap")} |');
  }

  // Per-spot detail.
  b.writeln('\n## Per-spot detail\n');
  b.writeln('| id | bucket | board | hero | SPR | raw | DCE mult | '
      'EQR_emp | EQR_show | GTO top | EV gap |');
  b.writeln('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final r in rows) {
    b.writeln('| ${r["id"]} | ${r["bucket"]} | ${r["board"]} | ${r["heroCombo"]} | '
        '${_f(r["spr"])} | ${_f(r["rawEquity"])} | ${_f(r["dceMultiplier"])} | '
        '${_f(r["eqrEmp"])} | ${_f(r["eqrShow"])} | ${r["gtoTopAction"]} | '
        '${_f(r["evGap"])} |');
  }

  // Coverage note (no silent caps).
  b.writeln('\n## Coverage\n');
  b.writeln('Buckets discovered: ${byBucket.keys.length} '
      '(${byBucket.keys.toList()..sort()}).');
  for (final e in byBucket.entries) {
    if (e.value.length > maxPerBucket) {
      b.writeln('- ${e.key}: ${e.value.length} available, capped at $maxPerBucket.');
    }
  }
  File(_reportPath).writeAsStringSync(b.toString());
}

double? _r(double? x) => x == null ? null : double.parse(x.toStringAsFixed(4));
String _f(dynamic x) => x is num ? x.toStringAsFixed(2) : '–';

List<PlayerRead> _parseReads(dynamic raw) {
  if (raw is! List) return const [];
  final now = DateTime.utc(2026, 1, 1);
  return raw.map((r) {
    final m = r as Map<String, dynamic>;
    return PlayerRead(
      id: 'batch',
      userId: 'batch',
      playerLabel: m['playerLabel'] as String,
      tags: (m['tags'] as List).cast<String>(),
      createdAt: now,
      updatedAt: now,
    );
  }).toList();
}
