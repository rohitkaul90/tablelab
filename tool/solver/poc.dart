// Proof-of-concept driver for the TexasSolver bridge.
//
// Proves the end-to-end path hand -> solver input -> solve -> parsed GTO action
// on (1) one eval fixture flop spot and (2) one real recorded hand (if exported
// to tool/solver/real_hand.json). For each spot it prints the solver's GTO
// strategy for hero's exact hand alongside the DCE FACTs the AI coach receives
// (realized equity, SPR), so we can eyeball agreement.
//
// Run:  dart run tool/solver/poc.dart
// (Requires TEXASSOLVER_DIR / solver_config.json — see run_solver.dart.)

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';
import 'package:tablelab/models/player_read.dart';

import 'run_solver.dart';
import 'solver_input.dart';

const _fixturePath = 'tool/eval/fixtures/pluribus-100b-117-p6.json';
const _realHandPath = 'tool/solver/real_hand.json';

Future<void> main() async {
  final out = StringBuffer();
  void emit(String s) {
    stdout.writeln(s);
    out.writeln(s);
  }

  emit('# TexasSolver bridge — POC findings\n');

  // (1) Fixture spot — deterministic, baked DCE labels.
  final fx = jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
  final fxHand = PokerHand.fromJson(fx['hand'] as Map<String, dynamic>);
  final fxReads = _parseReads(fx['reads']);
  await _runSpot(emit, 'FIXTURE  ($_fixturePath)', fxHand, fxReads,
      bakedLabels: fx['labels'] as Map<String, dynamic>?);

  // (2) Real recorded hand — exported to real_hand.json (hand + optional reads).
  final realFile = File(_realHandPath);
  if (realFile.existsSync()) {
    final rj = jsonDecode(realFile.readAsStringSync()) as Map<String, dynamic>;
    final realHand = PokerHand.fromJson(
        (rj['hand'] ?? rj) as Map<String, dynamic>);
    final realReads = _parseReads(rj['reads']);
    await _runSpot(emit, 'REAL HAND ($_realHandPath)', realHand, realReads);
  } else {
    emit('\n## Real hand — SKIPPED');
    emit('No $_realHandPath found. Export one with '
        '`dart run tool/solver/export_one_hand.dart` (needs SUPABASE_URL + '
        'SUPABASE_SERVICE_ROLE_KEY) or paste a hand `toJson()` into that file '
        'as {"hand": {...}, "reads": []}.');
  }

  File('tool/solver/POC_FINDINGS.md').writeAsStringSync(out.toString());
  stdout.writeln('\nWrote tool/solver/POC_FINDINGS.md');
}

Future<void> _runSpot(
  void Function(String) emit,
  String label,
  PokerHand hand,
  List<PlayerRead> reads, {
  Map<String, dynamic>? bakedLabels,
}) async {
  emit('\n## $label');
  final SolverSpot spot;
  try {
    spot = SolverSpot.fromHand(hand);
  } on UnsupportedSpot catch (e) {
    emit('  SKIPPED — ${e.reason}');
    return;
  }

  emit('  Board: ${spot.board.join(" ")}   Hero: ${spot.heroCombo}   '
      '${spot.heroIsIp ? "IP" : "OOP"}');
  emit('  Ranges: ${spot.rangeTrail}');
  emit('  IP range : ${_short(spot.rangeIp)}');
  emit('  OOP range: ${_short(spot.rangeOop)}');

  // Live DCE FACTs (exactly what the AI coach receives) for this hand.
  final check = await computeHandEquityCheck(hand, reads: reads, seed: 1234);
  final facts = check != null ? equityCheckFacts(check) : const <String>[];

  // Solve.
  emit('  Solving (this can take ~30-60s)...');
  final SolveResult res;
  try {
    res = await solve(spot);
  } catch (e) {
    emit('  SOLVER ERROR — $e');
    return;
  }

  emit('\n  → SOLVER GTO (hero ${spot.heroCombo} at the decision node):');
  emit('      strategy: ${res.formatted()}');
  emit('      EV chips: ${res.formattedEv()}');
  final ev = res.topActionEv;
  if (ev != null) {
    final pct = (ev / spot.pot * 100).toStringAsFixed(0);
    emit('      best-action EV ${ev.toStringAsFixed(1)} chips '
        '(= $pct% of the ${spot.pot}-chip flop pot)');
  }
  emit('      top action: ${res.topAction}'
      '   exploitability: ${res.exploitability?.toStringAsFixed(3) ?? "?"}%'
      '   solve: ${(res.wallMs / 1000).toStringAsFixed(1)}s');

  emit('\n  → DCE FACTs given to the AI coach:');
  for (final f in facts.where((f) =>
      f.contains('REALIZATION') || f.contains('SPR') || f.contains('Hero equity'))) {
    emit('      ${_short(f, 240)}');
  }
  if (bakedLabels != null) {
    emit('      (baked) realized=${bakedLabels['realizedEquityByStreet']}  '
        'spr=${bakedLabels['sprByStreet']}  forced=${bakedLabels['forcedDecision']}');
  }
}

String _short(String s, [int n = 90]) =>
    s.length <= n ? s : '${s.substring(0, n)}…';

List<PlayerRead> _parseReads(dynamic raw) {
  if (raw is! List) return const [];
  final now = DateTime.utc(2026, 1, 1);
  return raw.map((r) {
    final m = r as Map<String, dynamic>;
    return PlayerRead(
      id: 'poc',
      userId: 'poc',
      playerLabel: m['playerLabel'] as String,
      tags: (m['tags'] as List).cast<String>(),
      createdAt: now,
      updatedAt: now,
    );
  }).toList();
}
