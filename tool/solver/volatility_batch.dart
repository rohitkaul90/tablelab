// Board-volatility calibration batch for the TexasSolver bridge (DCE Tier A).
//
// Validates the Phase-1 `boardDynamism()` metric against the solver's actual GTO
// behaviour: do boards the metric calls DYNAMIC get larger / more frequent c-bets
// and a bigger turn-to-turn sizing swing than boards it calls STATIC? Output: a
// resumable per-spot JSON + `volatility_report.md` correlating, per spot:
//
//   • boardDynamism: dynamic-fraction + flush/straight/pair subset counts (Phase 1)
//   • hero equity SPREAD across the 47 turns (pure `lib/equity/`, no solver) —
//     the equity-variance candidate metric
//   • GTO flop c-bet sizing: range-aggregate bet freq + avg size (% pot)
//   • GTO turn sizing DISPERSION: stdev of the IP turn c-bet size/freq across the
//     turn chance node's per-card children (needs the dumpRounds=2 turn walk)
//
//   dart run tool/solver/volatility_batch.dart [totalCap=24]
//
// Spots are STRATIFIED across the dynamism range (most-static → most-dynamic) so a
// single run spans textures, unlike batch.dart's hand-class buckets. Resumable
// (id + inputs/solve-config signature). Each solve is minutes → hours-long
// BACKGROUND run. Operator-only (licensed solver, local). Solve settings are
// env-tunable via run_solver.dart (TLSOLVE_*). See SOLVER_PRIMER.md §6 for the
// turn-walk design this implements.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/decision_context.dart';
import 'package:tablelab/equity/simulator.dart';
import 'package:tablelab/models/hand_model.dart';

import 'run_solver.dart';
import 'solver_input.dart';

const _fixturesDir = 'tool/eval/fixtures';
const _realHandPath = 'tool/solver/real_hand.json';
const _resultsPath = 'tool/solver/volatility_results.json';
const _reportPath = 'tool/solver/volatility_report.md';

/// Iterations for the per-turn hero-equity Monte Carlo (47 turns × this × spots —
/// cheap relative to the solves, which dominate wall time).
const _eqIters = 4000;

class _Cand {
  final String id;
  final PokerHand hand;
  final SolverSpot spot;
  final BoardDynamism dyn;
  _Cand(this.id, this.hand, this.spot, this.dyn);
  double get dynFrac => dyn.dynamicFraction;
}

Future<void> main(List<String> args) async {
  final totalCap = args.isNotEmpty ? int.parse(args[0]) : 24;

  // ── 1. Gather solver-mappable, no-reads candidates with a classifiable flop. ──
  final cands = <_Cand>[];
  var skipped = 0;
  for (final f in Directory(_fixturesDir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final fx = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    if (_hasReads(fx['reads'])) continue; // GTO baseline only
    final c = _mapCandidate(fx['id'] as String, fx['hand'] as Map<String, dynamic>);
    if (c == null) {
      skipped++;
    } else {
      cands.add(c);
    }
  }
  final realFile = File(_realHandPath);
  if (realFile.existsSync()) {
    final rj = jsonDecode(realFile.readAsStringSync()) as Map<String, dynamic>;
    final hj = (rj['hand'] ?? rj) as Map<String, dynamic>;
    if (!_hasReads(rj['reads'])) {
      final c = _mapCandidate('real:${hj['id'] ?? 'hand'}', hj);
      if (c != null) cands.add(c);
    }
  }
  stdout.writeln('Mappable candidates: ${cands.length} (skipped $skipped '
      'unsupported/unclassifiable).');
  if (cands.isEmpty) {
    stderr.writeln('No candidates — nothing to solve.');
    return;
  }

  // ── 2. Stratify across the dynamism range so the run spans textures. ──
  cands.sort((a, b) => a.dynFrac.compareTo(b.dynFrac));
  final selected = _stratify(cands, totalCap);
  stdout.writeln('Selected ${selected.length}/${cands.length} spots, stratified '
      'over dynamic-fraction ${selected.first.dynFrac.toStringAsFixed(2)}…'
      '${selected.last.dynFrac.toStringAsFixed(2)}.');

  // ── 3. Solve + measure. Resumable cache keyed on id + inputs/config signature. ──
  final results = <String, dynamic>{};
  final resultsFile = File(_resultsPath);
  if (resultsFile.existsSync()) {
    results.addAll(jsonDecode(resultsFile.readAsStringSync()) as Map<String, dynamic>);
    stdout.writeln('Resuming: ${results.length} spots in cache.');
  }

  final errored = <String>[];
  var n = 0;
  for (final c in selected) {
    n++;
    final sig = _sig(c.spot);
    final cached = results[c.id];
    if (cached is Map && cached['sig'] == sig) {
      stdout.writeln('[$n/${selected.length}] ${c.id} — cached, skip.');
      continue;
    }
    stdout.writeln('[$n/${selected.length}] ${c.id} '
        '(dyn ${c.dynFrac.toStringAsFixed(2)}, board ${c.spot.board.join(" ")}) solving…');

    // Pure-Dart hero equity spread across the 47 turns (no solver).
    final eq = _turnEquitySpread(c.spot);

    TreeSolveResult tree;
    try {
      // Force the 'vol' bet profile: multiple sizes per street so the GTO size
      // CHOICE is observable (the calibration signal), no raise/allin so the
      // deep single-raised tree stays tractable. Not env-dependent.
      tree = await solveRoot(c.spot, dumpRounds: 2, betProfile: 'vol');
    } catch (e) {
      stdout.writeln('   ERROR: $e');
      errored.add(c.id);
      continue;
    }

    final m = _measure(c, tree, eq);
    m['sig'] = sig;
    results[c.id] = m;
    resultsFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    stdout.writeln('   flop cbet ${(m["flopBetFreq"] as num).toStringAsFixed(2)}freq '
        '@${(m["flopAvgSizePct"] as num).toStringAsFixed(0)}%  ·  '
        'turn size σ ${(m["turnSizeStdev"] as num?)?.toStringAsFixed(1) ?? "—"}  ·  '
        'eq range ${((m["eqRange"] as num? ?? 0) * 100).toStringAsFixed(0)}pts  '
        '(${(tree.wallMs / 1000).toStringAsFixed(0)}s, expl '
        '${tree.exploitability?.toStringAsFixed(2) ?? "?"}%)');
  }

  // ── 4. Report. ──
  final selIds = selected.map((c) => c.id).toSet();
  _writeReport(results, selIds, errored);
  stdout.writeln('\nWrote $_reportPath (${selIds.length} selected, '
      '${errored.length} errored; cache has ${results.length}).');
}

bool _hasReads(dynamic reads) => reads is List && reads.isNotEmpty;

/// Map a fixture hand → a _Cand, or null if unsupported / unclassifiable flop.
_Cand? _mapCandidate(String id, Map<String, dynamic> handJson) {
  final hand = PokerHand.fromJson(handJson);
  final SolverSpot spot;
  try {
    spot = SolverSpot.fromHand(hand);
  } catch (_) {
    return null;
  }
  final board = spot.board.map(parseCard).where((c) => c >= 0).toList();
  final dyn = boardDynamism(board);
  if (dyn == null) return null;
  return _Cand(id, hand, spot, dyn);
}

/// Pick [cap] evenly-spaced spots from the dynamism-sorted [sorted] (dedup on id).
List<_Cand> _stratify(List<_Cand> sorted, int cap) {
  if (sorted.length <= cap || cap <= 1) return List.of(sorted);
  final picked = <String, _Cand>{};
  for (var i = 0; i < cap; i++) {
    final idx = (i * (sorted.length - 1) / (cap - 1)).round();
    picked[sorted[idx].id] = sorted[idx];
  }
  // Rounding collisions can leave < cap; backfill with the nearest unused spots.
  for (var i = 0; i < sorted.length && picked.length < cap; i++) {
    picked.putIfAbsent(sorted[i].id, () => sorted[i]);
  }
  final out = picked.values.toList()..sort((a, b) => a.dynFrac.compareTo(b.dynFrac));
  return out;
}

/// Hero equity vs the opponent's GTO range across every unseen turn card —
/// the equity-variance volatility metric, computed on-device (no solver).
EquitySpread? _turnEquitySpread(SolverSpot spot) {
  final hero = [
    parseCard(spot.heroCombo.substring(0, 2)),
    parseCard(spot.heroCombo.substring(2, 4)),
  ];
  if (hero.any((c) => c < 0)) return null;
  final flop = spot.board.map(parseCard).where((c) => c >= 0).toList();
  if (flop.length != 3) return null;
  final villainNotation = spot.heroIsIp ? spot.rangeOop : spot.rangeIp;
  final base = <int>{...hero, ...flop};

  final equities = <double>[];
  for (var turn = 0; turn < 52; turn++) {
    if (base.contains(turn)) continue;
    final dead = {...base, turn};
    final villain = _expandRange(villainNotation, dead);
    if (villain.isEmpty) continue;
    final res = runSimulationSync(
      ranges: [
        [hero],
        villain,
      ],
      boardCards: [...flop, turn],
      iterations: _eqIters,
      seed: 7,
    );
    equities.add(res.equity[0]);
  }
  return equitySpread(equities);
}

/// Expand a comma-joined notation range ("AA,AKs,65s,…") to concrete combos,
/// excluding [dead] cards.
List<List<int>> _expandRange(String notation, Set<int> dead) {
  final out = <List<int>>[];
  for (final tok in notation.split(',')) {
    final t = tok.trim();
    if (t.isEmpty) continue;
    final (r, c) = handToCell(t);
    if (r < 0 || c < 0) continue;
    for (final pair in expandCell(r, c, exclude: dead)) {
      out.add([pair.$1, pair.$2]);
    }
  }
  return out;
}

/// Read the GTO sizing signals out of the solved [tree] for candidate [c].
Map<String, dynamic> _measure(_Cand c, TreeSolveResult tree, EquitySpread? eq) {
  final pot = c.spot.pot;

  // Flop c-bet: IP's node after OOP checks (the preflop raiser's c-bet).
  ({double betFreq, double avgSizePct})? flop;
  Map<String, dynamic>? flopClassSizing;
  final cbetNode = followChildren(tree.root, ['CHECK']);
  final flopInts = c.spot.board.map(parseCard).where((x) => x >= 0).toList();
  if (cbetNode != null) {
    final agg = nodeAggregateStrategy(cbetNode);
    if (agg != null) flop = _sizing(agg, pot);
    // Per-hand-class c-bet sizing — the prescriptive-sizing signal. Range-
    // aggregate sizing mixes all hands; the prescription is conditioned on
    // hero's class (a strongMade bets big for protection on a wet board even as
    // the range checks more), so bucket each combo by HandClass vs the flop.
    flopClassSizing = _classSizing(cbetNode, flopInts, pot);
  }

  // Turn dispersion: walk the check–check line to the turn chance node, then for
  // each per-card child read IP's turn c-bet (OOP checks → IP decides). Pot is
  // unchanged on a check-through, so size% is vs the same flop pot. A chance
  // node stores its per-card children under `dealcards` (keyed by card string),
  // NOT `childrens`; it enumerates the whole deck, so skip board/hero cards.
  final dead = <int>{
    ...c.spot.board.map(parseCard),
    parseCard(c.spot.heroCombo.substring(0, 2)),
    parseCard(c.spot.heroCombo.substring(2, 4)),
  };
  final turnSizes = <double>[];
  final turnBetFreqs = <double>[];
  var turnCards = 0;
  final chance = followChildren(tree.root, ['CHECK', 'CHECK']);
  final chanceKids = chance?['dealcards'];
  if (chanceKids is Map<String, dynamic>) {
    for (final entry in chanceKids.entries) {
      final turnCard = parseCard(entry.key);
      if (turnCard < 0 || dead.contains(turnCard)) continue; // board/hero/invalid
      final turnNode = entry.value;
      if (turnNode is! Map<String, dynamic>) continue;
      turnCards++;
      final ipTurn = followChildren(turnNode, ['CHECK']); // IP after OOP turn check
      final agg = ipTurn == null ? null : nodeAggregateStrategy(ipTurn);
      if (agg == null) continue;
      final s = _sizing(agg, pot);
      turnSizes.add(s.avgSizePct);
      turnBetFreqs.add(s.betFreq);
    }
  }
  final turnSizeSpread = equitySpread(turnSizes);
  final turnFreqSpread = equitySpread(turnBetFreqs);

  return {
    'id': c.id,
    'board': c.spot.board.join(' '),
    'heroCombo': c.spot.heroCombo,
    'heroIsIp': c.spot.heroIsIp,
    'spr': c.spot.effStack / c.spot.pot,
    // boardDynamism (Phase 1)
    'dynFrac': c.dyn.dynamicFraction,
    'dynamic': c.dyn.dynamic,
    'flushCards': c.dyn.flushCards,
    'straightCards': c.dyn.straightCards,
    'pairCards': c.dyn.pairCards,
    'isDynamic': c.dyn.isDynamic,
    // hero equity spread across turns (Dart)
    'eqMean': eq?.mean,
    'eqMin': eq?.min,
    'eqMax': eq?.max,
    'eqRange': eq?.range,
    'eqStdev': eq?.stdev,
    // solver GTO flop c-bet (range-aggregate + per-hand-class)
    'flopBetFreq': flop?.betFreq ?? 0.0,
    'flopAvgSizePct': flop?.avgSizePct ?? 0.0,
    'flopClassSizing': flopClassSizing,
    // solver GTO turn-to-turn dispersion
    'turnCards': turnCards,
    'turnSizeMean': turnSizeSpread?.mean,
    'turnSizeStdev': turnSizeSpread?.stdev,
    'turnBetFreqMean': turnFreqSpread?.mean,
    'turnBetFreqStdev': turnFreqSpread?.stdev,
    'exploitability': tree.exploitability,
    'wallMs': tree.wallMs,
  };
}

/// Range-aggregate bet frequency + average bet size (% of [pot]) from an action
/// node's mean strategy. All-in / huge-overbet sizes are capped at 250% so a
/// rare all-in (dumped as `BET <stack>`) can't blow up the size average.
({double betFreq, double avgSizePct}) _sizing(
    ({List<String> actions, List<double> freqs}) agg, num pot) {
  var betFreq = 0.0, weighted = 0.0;
  for (var i = 0; i < agg.actions.length; i++) {
    final a = agg.actions[i].toUpperCase();
    final isBet = a.startsWith('BET') || a.startsWith('RAISE') || a.startsWith('ALLIN');
    if (!isBet) continue;
    betFreq += agg.freqs[i];
    final amt = _amountOf(agg.actions[i]) ?? pot.toDouble();
    final pct = amt / pot * 100;
    weighted += agg.freqs[i] * (pct > 250 ? 250.0 : pct);
  }
  return (betFreq: betFreq, avgSizePct: betFreq > 0 ? weighted / betFreq : 0.0);
}

double? _amountOf(String action) {
  final m = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(action);
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// Bucket the combos at an action node by [HandClass] (vs [board]) and aggregate
/// bet frequency + average bet size (% of [pot]) per class — the per-hand-class
/// GTO sizing that conditions the prescription ("dynamic board + strongMade →
/// bigger size?"). Returns class-name → {betFreq, avgSizePct, n}, or null if the
/// node has no per-combo strategy.
Map<String, dynamic>? _classSizing(
    Map<String, dynamic> node, List<int> board, num pot) {
  final strat = node['strategy'] as Map<String, dynamic>?;
  if (strat == null) return null;
  final actions = (strat['actions'] as List).cast<String>();
  final byCombo = strat['strategy'] as Map<String, dynamic>?;
  if (byCombo == null || byCombo.isEmpty) return null;

  final agg = <HandClass, ({double betFreq, double sizeW, double sizeFreq, int n})>{};
  byCombo.forEach((combo, v) {
    if (v is! List || combo.length < 4) return;
    final hole = [parseCard(combo.substring(0, 2)), parseCard(combo.substring(2, 4))];
    if (hole.any((x) => x < 0)) return;
    final hc = classifyHandClass(hole, board);
    if (hc == null) return;
    final freqs = v.map((e) => (e as num).toDouble()).toList();
    final s = _sizing((actions: actions, freqs: freqs), pot);
    final p = agg[hc] ?? (betFreq: 0.0, sizeW: 0.0, sizeFreq: 0.0, n: 0);
    agg[hc] = (
      betFreq: p.betFreq + s.betFreq,
      sizeW: p.sizeW + s.betFreq * s.avgSizePct,
      sizeFreq: p.sizeFreq + s.betFreq,
      n: p.n + 1,
    );
  });
  return {
    for (final e in agg.entries)
      e.key.name: {
        'betFreq': e.value.n > 0 ? e.value.betFreq / e.value.n : 0.0,
        'avgSizePct': e.value.sizeFreq > 0 ? e.value.sizeW / e.value.sizeFreq : 0.0,
        'n': e.value.n,
      },
  };
}

/// Inputs signature — an edited fixture / mapping / solve-setting re-solves.
String _sig(SolverSpot s) => [
      s.board.join(),
      s.rangeIp,
      s.rangeOop,
      s.pot,
      s.effStack,
      s.heroCombo,
      s.heroIsIp,
      'dump2',
      'vol', // forced bet profile (overrides env), part of what determines the solve
      solverConfigTag(), // accuracy + maxIter (the env profile portion is moot here)
    ].join('|');

// ── Report ───────────────────────────────────────────────────────────────────

void _writeReport(
    Map<String, dynamic> results, Set<String> selectedIds, List<String> errored) {
  final rows = <Map<String, dynamic>>[
    for (final id in selectedIds)
      if (results[id] is Map<String, dynamic>) results[id] as Map<String, dynamic>,
  ]..sort((a, b) => (a['dynFrac'] as num).compareTo(b['dynFrac'] as num));

  final b = StringBuffer()
    ..writeln('# Board-volatility calibration report')
    ..writeln()
    ..writeln('Validates `boardDynamism()` (Phase 1) against the solver\'s GTO '
        'c-bet sizing and turn-to-turn sizing swing. Static vs dynamic split on '
        'the PLACEHOLDER `kBoardDynamicThreshold` — use the aggregate below to '
        'RE-SET that threshold and the sizing buckets. Heads-up single-raised flop '
        'spots; sizes are % of the flop pot.')
    ..writeln()
    ..writeln('Spots: ${rows.length}'
        '${errored.isEmpty ? '' : ' · errored (excluded): ${errored.join(', ')}'}')
    ..writeln();

  // Per-spot table.
  b
    ..writeln('## Per spot (sorted by dynamic-fraction)')
    ..writeln()
    ..writeln('| spot | board | dyn% | f/s/p | eq range | flop cbet | turn size σ | expl% |')
    ..writeln('|---|---|--:|---|--:|---|--:|--:|');
  for (final r in rows) {
    final dynPct = ((r['dynFrac'] as num) * 100).toStringAsFixed(0);
    final fsp = '${r['flushCards']}/${r['straightCards']}/${r['pairCards']}';
    final eqRange = r['eqRange'] == null
        ? '—'
        : '${((r['eqRange'] as num) * 100).toStringAsFixed(0)}pt';
    final cbet = '${((r['flopBetFreq'] as num) * 100).toStringAsFixed(0)}% @ '
        '${(r['flopAvgSizePct'] as num).toStringAsFixed(0)}%';
    final tsig = (r['turnSizeStdev'] as num?)?.toStringAsFixed(1) ?? '—';
    final expl = (r['exploitability'] as num?)?.toStringAsFixed(2) ?? '?';
    b.writeln('| ${r['id']} | ${r['board']} | $dynPct${(r['isDynamic'] as bool) ? '*' : ''} '
        '| $fsp | $eqRange | $cbet | $tsig | $expl |');
  }
  b
    ..writeln()
    ..writeln('`dyn%` = fraction of unseen turns that change the board (`*` = past '
        'the placeholder threshold); `f/s/p` = flush / straight / pair subset '
        'counts; `eq range` = hero equity max−min across turns; `flop cbet` = GTO '
        'range-aggregate bet freq @ avg size; `turn size σ` = stdev of the IP turn '
        'c-bet size across the turn chance node\'s children.')
    ..writeln();

  // Aggregate: does dynamism track the GTO signals? Split at the placeholder
  // threshold AND report a tertile breakdown so the threshold can be re-set.
  b
    ..writeln('## Aggregate — does dynamism predict GTO sizing?')
    ..writeln();
  final staticRows = rows.where((r) => !(r['isDynamic'] as bool)).toList();
  final dynamicRows = rows.where((r) => r['isDynamic'] as bool).toList();
  _aggBlock(b, 'Static (below threshold)', staticRows);
  _aggBlock(b, 'Dynamic (at/above threshold)', dynamicRows);

  // The prescription signal: GTO c-bet sizing per hand class, static vs dynamic.
  // This is what conditions the dynamic→bigger prescription on hero's class —
  // the range aggregate above mixes all hands and can read backwards.
  b
    ..writeln('### GTO flop c-bet by hand class — static vs dynamic '
        '(the prescription signal)')
    ..writeln();
  _classAggBlock(b, 'Static boards', staticRows);
  _classAggBlock(b, 'Dynamic boards', dynamicRows);

  // Tertiles by dynamic-fraction (threshold-independent).
  if (rows.length >= 3) {
    final t = rows.length ~/ 3;
    b.writeln('### By dynamic-fraction tertile');
    _aggBlock(b, 'Low third (most static)', rows.sublist(0, t));
    _aggBlock(b, 'Middle third', rows.sublist(t, rows.length - t));
    _aggBlock(b, 'High third (most dynamic)', rows.sublist(rows.length - t));
  }

  b
    ..writeln('---')
    ..writeln('_Operator-only; regenerated by `dart run tool/solver/volatility_batch.dart`. '
        'Solver settings: see run_solver.dart. The numbers feed the Phase-3 refit of '
        '`kBoardDynamicThreshold` + the prescriptive sizing buckets in '
        '`decision_context.dart` (branch → PR → re-eval, per the EQR/SPR process)._');

  File(_reportPath).writeAsStringSync(b.toString());
}

void _aggBlock(StringBuffer b, String label, List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) {
    b.writeln('**$label** — (none)\n');
    return;
  }
  double mean(String k) {
    var s = 0.0, n = 0;
    for (final r in rows) {
      final v = r[k];
      if (v is num) {
        s += v;
        n++;
      }
    }
    return n == 0 ? 0 : s / n;
  }

  b
    ..writeln('**$label** (n=${rows.length})')
    ..writeln('- mean dynamic-fraction: ${(mean('dynFrac') * 100).toStringAsFixed(0)}%')
    ..writeln('- mean hero equity range across turns: '
        '${(mean('eqRange') * 100).toStringAsFixed(1)}pts')
    ..writeln('- mean GTO flop c-bet: ${(mean('flopBetFreq') * 100).toStringAsFixed(0)}% '
        'freq @ ${mean('flopAvgSizePct').toStringAsFixed(0)}% pot')
    ..writeln('- mean GTO turn size stdev: ${mean('turnSizeStdev').toStringAsFixed(1)}pts')
    ..writeln();
}

/// Per-hand-class GTO c-bet sizing, averaged over the spots in [rows] — the
/// table that calibrates the prescription. Each spot contributes its own
/// per-class {betFreq, avgSizePct}; we mean those across spots.
void _classAggBlock(StringBuffer b, String label, List<Map<String, dynamic>> rows) {
  const order = ['strongMade', 'marginalMade', 'strongDraw', 'weakDraw', 'air'];
  final acc = <String, ({double freq, double size, int spots, int combos})>{};
  for (final r in rows) {
    final cs = r['flopClassSizing'];
    if (cs is! Map) continue;
    cs.forEach((k, v) {
      if (v is! Map) return;
      final p = acc[k] ?? (freq: 0.0, size: 0.0, spots: 0, combos: 0);
      acc[k as String] = (
        freq: p.freq + (v['betFreq'] as num).toDouble(),
        size: p.size + (v['avgSizePct'] as num).toDouble(),
        spots: p.spots + 1,
        combos: p.combos + (v['n'] as num).toInt(),
      );
    });
  }
  if (acc.isEmpty) {
    b.writeln('**$label** — (no class data)\n');
    return;
  }
  b
    ..writeln('**$label** (mean over spots)')
    ..writeln()
    ..writeln('| hand class | bet freq | avg size % | spots · combos |')
    ..writeln('|---|--:|--:|--:|');
  for (final k in order) {
    final v = acc[k];
    if (v == null) continue;
    b.writeln('| $k | ${(v.freq / v.spots * 100).toStringAsFixed(0)}% | '
        '${(v.size / v.spots).toStringAsFixed(0)}% | ${v.spots} · ${v.combos} |');
  }
  b.writeln();
}
