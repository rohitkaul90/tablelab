// DCE Q2 — Phase 2. Systematic calibration batch: across no-reads HU FLOP spots,
// measure how far the equity ENGINE's heuristic flop hero-equity (its range
// narrowing) is from the SOLVER's reach-weighted GTO hero-equity, for villain's
// matched flop action, bucketed by {villain action × board texture × SPR}.
// Output: resumable per-spot JSON + range_calib_report.md = the per-bucket gaps
// that tell us which villain_range narrowing params to refit (Phase 3).
//
//   dart run tool/solver/range_calib_batch.dart [maxSpots=60]
//
// FLOP only (the bridge's solid surface; turn/river = a follow-on). Matches the
// villain's recorded flop action to a solver action: check → CHECK; a bet → the
// nearest solver size (vol profile = 33% / 75%). Heavy multi-bet solves are
// minutes each → an hours-long BACKGROUND run. Operator-only (licensed solver).

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';

import 'range_calib.dart';
import 'run_solver.dart';
import 'solver_input.dart';

const _fixturesDir = 'tool/eval/fixtures';
const _resultsPath = 'tool/solver/range_calib_results.json';
const _reportPath = 'tool/solver/range_calib_report.md';

Future<void> main(List<String> args) async {
  final maxSpots = args.isNotEmpty ? int.parse(args[0]) : 60;

  // ── Gather no-reads, solver-mappable HU flop candidates. ──
  final cands = <(String id, PokerHand hand, SolverSpot spot)>[];
  for (final f in Directory(_fixturesDir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final fx = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    if (fx['reads'] is List && (fx['reads'] as List).isNotEmpty) continue;
    final hand = PokerHand.fromJson(fx['hand'] as Map<String, dynamic>);
    try {
      cands.add((fx['id'] as String, hand, SolverSpot.fromHand(hand)));
    } catch (_) {/* unsupported */}
  }
  cands.sort((a, b) => a.$1.compareTo(b.$1));
  final selected = cands.take(maxSpots).toList();
  stdout.writeln('Candidates: ${cands.length} mappable; solving ${selected.length}.');

  // ── Resumable cache (id + inputs/config signature). ──
  final results = <String, dynamic>{};
  final resultsFile = File(_resultsPath);
  if (resultsFile.existsSync()) {
    results.addAll(jsonDecode(resultsFile.readAsStringSync()) as Map<String, dynamic>);
    stdout.writeln('Resuming: ${results.length} cached.');
  }

  var n = 0, errored = 0;
  for (final (id, hand, spot) in selected) {
    n++;
    final sig = _sig(spot);
    final cached = results[id];
    if (cached is Map && cached['sig'] == sig) {
      stdout.writeln('[$n/${selected.length}] $id — cached.');
      continue;
    }
    stdout.writeln('[$n/${selected.length}] $id (${spot.board.join(" ")}) solving…');
    Map<String, dynamic>? row;
    try {
      row = await _measure(id, hand, spot);
    } catch (e) {
      stdout.writeln('   ERROR: $e');
      errored++;
      continue;
    }
    if (row == null) {
      stdout.writeln('   skip (could not match villain flop action / node).');
      continue;
    }
    row['sig'] = sig;
    results[id] = row;
    resultsFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    stdout.writeln('   villain ${row["action"]}  solverEq '
        '${(row["solverEq"] as num).toStringAsFixed(1)}%  engineEq '
        '${(row["engineEq"] as num).toStringAsFixed(1)}%  gap '
        '${(row["gap"] as num).toStringAsFixed(1)}pt  [${row["boardBucket"]}, ${row["sprBucket"]}]');
  }

  _writeReport(results, selected.map((s) => s.$1).toSet(), errored);
  stdout.writeln('\nWrote $_reportPath (${results.length} cached, $errored errored).');
}

/// Solve the spot and measure {solver reach-weighted hero-equity vs villain's
/// matched flop range} vs {engine heuristic flop hero-equity}. Null if the
/// villain flop action / node can't be matched (e.g. hero OOP led the flop).
Future<Map<String, dynamic>?> _measure(
    String id, PokerHand hand, SolverSpot spot) async {
  final hero = [
    parseCard(spot.heroCombo.substring(0, 2)),
    parseCard(spot.heroCombo.substring(2, 4)),
  ];
  final board = spot.board.map(parseCard).toList();
  final heroSeat = hand.tableSetup.heroSeat;

  // Villain's strongest recorded FLOP action (bet/raise outrank check).
  final flop = hand.streets.firstWhere((s) => s.street == Street.flop,
      orElse: () => throw StateError('no flop'));
  HandAction? villainAct;
  for (final a in flop.actions) {
    if (a.seat == heroSeat) continue;
    if (villainAct == null || _rank(a.type) > _rank(villainAct.type)) villainAct = a;
  }
  if (villainAct == null) return null;
  // No ActionType.bet — a bet is recorded as `raise` (with openingBet). Aggressive
  // = raise/all-in; everything else (check) maps to the solver's CHECK action.
  final isBet = villainAct.type == ActionType.raise ||
      villainAct.type == ActionType.allIn;

  // Solve, then locate villain's flop action node.
  final tree = await solveRoot(spot, dumpRounds: 2, betProfile: 'vol');
  // heroIsIp → villain (OOP) acts first → root. hero OOP → hero acts first; only
  // the hero-checks line is followable (the bridge maps hero-OOP with empty path).
  Map<String, dynamic>? villainNode;
  if (spot.heroIsIp) {
    villainNode = tree.root;
  } else {
    villainNode = followChildren(tree.root, ['CHECK']); // villain IP after hero check
  }
  if (villainNode == null) return null;

  final actions = nodeActions(villainNode);
  if (actions.isEmpty) return null;
  final idx = _matchActionIdx(actions, isBet, villainAct.amount, spot.pot);
  if (idx < 0) return null;

  final range = nodeActionRange(villainNode, idx);
  if (range.isEmpty) return null;
  final solverEq = heroEquityVsWeightedRange(hero, board, range);
  if (solverEq.isNaN) return null;

  // Engine's heuristic flop number.
  final check = await computeHandEquityCheck(hand, reads: const [], seed: 1234);
  double? engineEq;
  for (final s in check?.streets ?? const <StreetEquityCheck>[]) {
    if (s.street == Street.flop) engineEq = s.heroEquity;
  }
  if (engineEq == null) return null;

  return {
    'id': id,
    'villainPos': spot.heroIsIp ? 'OOP' : 'IP',
    'action': actions[idx].split(' ').first.toLowerCase() == 'bet'
        ? (idx == _firstBetIdx(actions) ? 'bet-small' : 'bet-big')
        : 'check',
    'solverEq': solverEq * 100,
    'engineEq': engineEq * 100,
    'gap': (engineEq - solverEq) * 100, // engine − solver (negative = engine understates)
    'boardBucket': _boardBucket(board),
    'sprBucket': _sprBucket(spot.effStack / spot.pot),
    'spr': spot.effStack / spot.pot,
    'expl': tree.exploitability,
  };
}

int _rank(ActionType t) => switch (t) {
      ActionType.allIn => 4,
      ActionType.raise => 3, // a bet is recorded as raise+openingBet
      ActionType.call => 1,
      _ => 0, // check/fold
    };

/// Index of villain's action at a node: a check → the CHECK action; a bet → the
/// solver bet size nearest the recorded bet fraction.
int _matchActionIdx(List<String> actions, bool isBet, int? betAmt, int pot) {
  if (!isBet) {
    return actions.indexWhere((a) => a.toUpperCase().startsWith('CHECK'));
  }
  // bet sizes available (sorted ascending by amount), match nearest fraction.
  final bets = <(int idx, double frac)>[];
  for (var i = 0; i < actions.length; i++) {
    final a = actions[i];
    if (!a.toUpperCase().startsWith('BET')) continue;
    final m = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(a);
    if (m == null) continue;
    bets.add((i, double.parse(m.group(1)!) / pot));
  }
  if (bets.isEmpty) return -1;
  final target = pot > 0 ? (betAmt ?? pot) / pot : 0.5;
  bets.sort((a, b) => (a.$2 - target).abs().compareTo((b.$2 - target).abs()));
  return bets.first.$1;
}

int _firstBetIdx(List<String> actions) =>
    actions.indexWhere((a) => a.toUpperCase().startsWith('BET'));

String _boardBucket(List<int> board) {
  final ranks = board.map(cardRank).toList();
  final paired = ranks.toSet().length < ranks.length;
  final suitCount = <int, int>{};
  for (final c in board) {
    final s = cardSuit(c);
    suitCount[s] = (suitCount[s] ?? 0) + 1;
  }
  final maxSuit = suitCount.values.fold(0, (a, b) => a > b ? a : b);
  if (paired) return 'paired';
  if (maxSuit >= 3) return 'monotone';
  if (maxSuit == 2) return 'two-tone';
  return 'rainbow';
}

String _sprBucket(double spr) =>
    spr < 4 ? 'low(<4)' : (spr <= 10 ? 'mid(4-10)' : 'high(>10)');

String _sig(SolverSpot s) => [
      s.board.join(),
      s.rangeIp,
      s.rangeOop,
      s.pot,
      s.effStack,
      s.heroCombo,
      s.heroIsIp,
      'rangecalib-v1',
      solverConfigTag(),
    ].join('|');

// ── Report ───────────────────────────────────────────────────────────────────

void _writeReport(Map<String, dynamic> results, Set<String> ids, int errored) {
  final rows = <Map<String, dynamic>>[
    for (final id in ids)
      if (results[id] is Map<String, dynamic>) results[id] as Map<String, dynamic>,
  ]..sort((a, b) => (a['gap'] as num).abs().compareTo((b['gap'] as num).abs()));

  final b = StringBuffer()
    ..writeln('# Range-narrowing calibration (DCE Q2)')
    ..writeln()
    ..writeln('Per FLOP spot: ENGINE heuristic hero-equity (its range narrowing on '
        "villain's matched flop action) vs SOLVER reach-weighted GTO hero-equity. "
        '`gap` = engine − solver (NEGATIVE = engine UNDERSTATES hero, i.e. models '
        "villain's range too strong; POSITIVE = engine overstates).")
    ..writeln()
    ..writeln('Spots: ${rows.length}${errored == 0 ? '' : ' · errored: $errored'}')
    ..writeln();

  // Aggregate by {action × board bucket}.
  b
    ..writeln('## Mean gap by villain action × board texture')
    ..writeln()
    ..writeln('| action | board | n | mean engineEq | mean solverEq | mean gap (pt) |')
    ..writeln('|---|---|--:|--:|--:|--:|');
  final buckets = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    buckets.putIfAbsent('${r["action"]}|${r["boardBucket"]}', () => []).add(r);
  }
  final keys = buckets.keys.toList()..sort();
  for (final k in keys) {
    final g = buckets[k]!;
    double mean(String f) => g.fold<double>(0, (s, r) => s + (r[f] as num)) / g.length;
    final parts = k.split('|');
    b.writeln('| ${parts[0]} | ${parts[1]} | ${g.length} | '
        '${mean('engineEq').toStringAsFixed(1)} | ${mean('solverEq').toStringAsFixed(1)} | '
        '${mean('gap').toStringAsFixed(1)} |');
  }
  b.writeln();

  // Aggregate by action only (the headline calibration signal).
  b
    ..writeln('## Mean gap by villain action (all boards)')
    ..writeln()
    ..writeln('| action | n | mean gap (pt) | mean |gap| |')
    ..writeln('|---|--:|--:|--:|');
  final byAct = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    byAct.putIfAbsent(r['action'] as String, () => []).add(r);
  }
  for (final k in byAct.keys.toList()..sort()) {
    final g = byAct[k]!;
    final mg = g.fold<double>(0, (s, r) => s + (r['gap'] as num)) / g.length;
    final mag = g.fold<double>(0, (s, r) => s + (r['gap'] as num).abs()) / g.length;
    b.writeln('| $k | ${g.length} | ${mg.toStringAsFixed(1)} | ${mag.toStringAsFixed(1)} |');
  }

  b
    ..writeln()
    ..writeln('---')
    ..writeln('_Operator-only; `dart run tool/solver/range_calib_batch.dart`. Feeds the '
        'Phase-3 refit of `villain_range.dart` narrowing params (branch → PR → re-eval)._');
  File(_reportPath).writeAsStringSync(b.toString());
}
