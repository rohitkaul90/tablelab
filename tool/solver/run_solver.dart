// Runs a [SolverSpot] through the locally-built TexasSolver console_solver and
// returns hero's GTO strategy at the decision node.
//
// The binary + resources live in the (Avira-excluded) license delivery folder;
// we invoke them IN PLACE — never copy the binary into the repo. Configure the
// path via the TEXASSOLVER_DIR env var or a gitignored tool/solver/solver_config.json
// of the form {"sourceDir": "C:\\...\\source"}.

import 'dart:convert';
import 'dart:io';

import 'solver_input.dart';

class SolveResult {
  final List<String> actions; // e.g. ["CHECK", "BET 50.0", ...]
  final List<double> probs; // hero combo's strategy, aligned to actions
  final List<double>? evs; // hero combo's per-action EV in chips (patched dump)
  final double? passiveEv; // hero combo's best check/call-only EV (showdown realization)
  final double? exploitability; // final total exploitability %, if parsed
  final int wallMs;
  final int? nodePlayer; // solver "player" at hero's node (sanity)

  SolveResult({
    required this.actions,
    required this.probs,
    required this.evs,
    required this.passiveEv,
    required this.exploitability,
    required this.wallMs,
    required this.nodePlayer,
  });

  /// EV (chips) of the highest-frequency action, or null if EVs absent.
  double? get topActionEv {
    if (evs == null || evs!.isEmpty) return null;
    var bi = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bi]) bi = i;
    }
    return bi < evs!.length ? evs![bi] : null;
  }

  String formattedEv() {
    if (evs == null) return '(no EV)';
    final parts = <String>[];
    for (var i = 0; i < actions.length && i < evs!.length; i++) {
      parts.add('${actions[i]} ${evs![i].toStringAsFixed(1)}');
    }
    return parts.join('  ·  ');
  }

  /// The single highest-frequency action.
  String get topAction {
    var bi = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bi]) bi = i;
    }
    return actions.isEmpty ? '(none)' : actions[bi];
  }

  String formatted() {
    final parts = <String>[];
    for (var i = 0; i < actions.length && i < probs.length; i++) {
      parts.add('${actions[i]} ${(probs[i] * 100).toStringAsFixed(1)}%');
    }
    return parts.join('  ·  ');
  }
}

String _sourceDir() {
  final env = Platform.environment['TEXASSOLVER_DIR'];
  if (env != null && env.trim().isNotEmpty) return env.trim();
  final cfg = File('tool/solver/solver_config.json');
  if (cfg.existsSync()) {
    final m = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
    final d = m['sourceDir'] as String?;
    if (d != null && d.trim().isNotEmpty) return d.trim();
  }
  throw StateError(
      'Set TEXASSOLVER_DIR or tool/solver/solver_config.json {"sourceDir": "..."} '
      'to the TexasSolver `source` dir (the one containing vsbuild/ and resources/).');
}

/// POC bet-size block: one bet size + all-in per street per player. Keeping the
/// branching factor low (2 actions/node, not 4) is what makes a DEEP spot
/// (high SPR → full flop+turn+river tree) solve in seconds rather than minutes.
/// The follow-on can widen this once we accept longer solves.
String _betSizes() {
  final b = StringBuffer();
  for (final pos in ['oop', 'ip']) {
    for (final street in ['flop', 'turn', 'river']) {
      b.writeln('set_bet_sizes $pos,$street,bet,50');
      b.writeln('set_bet_sizes $pos,$street,allin');
    }
  }
  return b.toString();
}

String _buildInput(SolverSpot spot, String dumpPath) {
  return '''
set_pot ${spot.pot}
set_effective_stack ${spot.effStack}
set_board ${spot.board.join(',')}
set_range_ip ${spot.rangeIp}
set_range_oop ${spot.rangeOop}
${_betSizes()}set_allin_threshold 0.67
build_tree
set_thread_num 16
set_accuracy 2.0
set_max_iteration 60
set_print_interval 10
set_use_isomorphism 1
start_solve
set_dump_rounds 1
dump_result $dumpPath
''';
}

double? _parseExploitability(String stdout) {
  final re = RegExp(r'Total exploitability\s+([0-9.]+)\s*precent', caseSensitive: false);
  double? last;
  for (final m in re.allMatches(stdout)) {
    last = double.tryParse(m.group(1)!);
  }
  return last;
}

/// Find hero's combo in a {combo: [values]} map, tolerant of card ordering.
List<double>? _comboVec(Map<String, dynamic>? s, String combo) {
  if (s == null) return null;
  final c1 = combo.substring(0, 2), c2 = combo.substring(2, 4);
  for (final key in [c1 + c2, c2 + c1]) {
    final v = s[key];
    if (v is List) return v.map((e) => (e as num).toDouble()).toList();
  }
  // Fallback: any key that is a permutation of the two cards.
  for (final entry in s.entries) {
    final k = entry.key;
    if (k.length == 4 &&
        ((k.startsWith(c1) && k.endsWith(c2)) ||
            (k.startsWith(c2) && k.endsWith(c1)))) {
      final v = entry.value;
      if (v is List) return v.map((e) => (e as num).toDouble()).toList();
    }
  }
  return null;
}

Future<SolveResult> solve(SolverSpot spot, {bool verbose = false}) async {
  final dir = _sourceDir();
  final bin = '$dir/vsbuild/console_solver.exe';
  if (!File(bin).existsSync()) {
    throw StateError('console_solver.exe not found at $bin — build it first.');
  }
  final tmp = Directory.systemTemp.createTempSync('tlsolve_');
  final inputPath = '${tmp.path}/input.txt';
  final dumpPath = '${tmp.path}/out.json';
  File(inputPath).writeAsStringSync(_buildInput(spot, dumpPath));

  final sw = Stopwatch()..start();
  final res = await Process.run(bin, ['-i', inputPath], workingDirectory: dir);
  sw.stop();
  if (verbose) {
    stdout.writeln(res.stdout.toString().split('\n').takeLast(4).join('\n'));
  }
  if (res.exitCode != 0) {
    throw StateError('solver exit ${res.exitCode}\n${res.stderr}\n${res.stdout}');
  }
  final outFile = File(dumpPath);
  if (!outFile.existsSync()) {
    throw StateError('solver produced no output_result\n${res.stdout}');
  }
  var node = jsonDecode(outFile.readAsStringSync()) as Map<String, dynamic>;
  for (final step in spot.heroPath) {
    final children = node['childrens'] as Map<String, dynamic>?;
    final key = children?.keys.firstWhere(
      (k) => k == step || k.toUpperCase().startsWith(step.toUpperCase()),
      orElse: () => '',
    );
    if (key == null || key.isEmpty) {
      throw StateError('could not follow "$step"; children: ${children?.keys.toList()}');
    }
    node = children![key] as Map<String, dynamic>;
  }
  final strat = node['strategy'] as Map<String, dynamic>?;
  if (strat == null) {
    throw StateError('hero node has no strategy (node_type ${node['node_type']})');
  }
  final actions = (strat['actions'] as List).cast<String>();
  final probs = _comboVec(strat['strategy'] as Map<String, dynamic>?, spot.heroCombo);
  if (probs == null) {
    throw StateError('hero combo ${spot.heroCombo} not in node strategy');
  }
  final evs = _comboVec(node['ev'] as Map<String, dynamic>?, spot.heroCombo);
  final passiveVec = _comboVec(node['ev_passive'] as Map<String, dynamic>?, spot.heroCombo);
  return SolveResult(
    actions: actions,
    probs: probs,
    evs: evs,
    passiveEv: (passiveVec != null && passiveVec.isNotEmpty) ? passiveVec.first : null,
    exploitability: _parseExploitability(res.stdout.toString()),
    wallMs: sw.elapsedMilliseconds,
    nodePlayer: node['player'] as int?,
  );
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int n) {
    final l = toList();
    return l.sublist(l.length - n < 0 ? 0 : l.length - n);
  }
}
