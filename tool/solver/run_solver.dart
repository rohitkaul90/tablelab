// Runs a [SolverSpot] through the locally-built TexasSolver console_solver and
// returns hero's GTO strategy at the decision node.
//
// The binary + resources live in the (Avira-excluded) license delivery folder;
// we invoke them IN PLACE — never copy the binary into the repo. Configure the
// path via the TEXASSOLVER_DIR env var or a gitignored tool/solver/solver_config.json
// of the form {"sourceDir": "C:\\...\\source"}.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'solver_input.dart';

/// One-shot guard so the resolved solver binary is logged once per process, not
/// per spot. See the [_invokeSolver] log site.
bool _loggedBin = false;

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

/// Resolve the built `console_solver` binary cross-platform. Windows builds to
/// `vsbuild/console_solver.exe`; the Linux/macOS CMake out-of-source build (the
/// big-RAM vCPU box used for deep-cash / river solves) produces
/// `build/console_solver`. `TEXASSOLVER_BIN` overrides both.
String _solverBin(String dir) {
  final override = Platform.environment['TEXASSOLVER_BIN'];
  if (override != null && override.trim().isNotEmpty) return override.trim();
  if (Platform.isWindows) return '$dir/vsbuild/console_solver.exe';
  for (final c in ['$dir/build/console_solver', '$dir/console_solver']) {
    if (File(c).existsSync()) return c;
  }
  return '$dir/build/console_solver';
}

/// Solve parameters, env-overridable so a calibration round can tighten without
/// editing code. Defaults are the "full realism" calibration settings.
class _SolveConfig {
  final double accuracy; // exploitability % stop threshold
  final int maxIter;
  final String betProfile; // 'multi' (tiered, realistic) | 'single' (fast POC)
  final int timeoutS; // per-spot wall-clock cap
  final int threads; // solver worker threads (peak memory scales with this)
  final String dumpFmt; // 'json' | 'bin' (TLSD) | 'both' (validation runs)

  _SolveConfig(this.accuracy, this.maxIter, this.betProfile, this.timeoutS,
      this.threads, this.dumpFmt);

  /// Compact descriptor — folded into the batch cache signature so a settings
  /// change invalidates cached solves (they'd otherwise be served stale). Thread
  /// count and dump FORMAT are intentionally EXCLUDED — they change solve
  /// speed/peak memory/artifact encoding, not the GTO result, so they must not
  /// invalidate cached solves.
  String get tag => 'acc$accuracy|it$maxIter|$betProfile';
}

_SolveConfig _config() {
  final e = Platform.environment;
  final accuracy = double.tryParse(e['TLSOLVE_ACCURACY'] ?? '') ?? 0.5;
  // Positive-int env knob with a fallback. A bare `int.tryParse(..) ?? default`
  // lets "0"/"-1" through (tryParse returns non-null), which would emit an
  // invalid solver command (e.g. set_thread_num 0 crashes the solve). Reject <1.
  int posInt(String key, int dflt) {
    final v = int.tryParse(e[key] ?? '');
    return (v != null && v > 0) ? v : dflt;
  }
  // 200 iters reaches ~0.5% on these deep single-bet spots (60 only reached ~5%).
  final maxIter = posInt('TLSOLVE_MAXITER', 200);
  // 'single' is the default: multi-bet OOMs on deep (SPR 15-20) spots; single
  // converges to ~0.5% within the tree's action space. Use 'multi' for shallow spots.
  var bets = (e['TLSOLVE_BETS'] ?? 'single').toLowerCase();
  const known = {'single', 'multi', 'vol', 'turn', 'river'};
  if (!known.contains(bets)) bets = 'single';
  final timeoutS = posInt('TLSOLVE_TIMEOUT_S', 900);
  // Worker threads. Default 16; lower (e.g. 8) to cut PEAK MEMORY / avoid the
  // concurrency-race access violation (exit -1073741819) on the branchiest
  // turn-raise trees. Result is identical (not in the cache tag).
  final threads = posInt('TLSOLVE_THREADS', 16);
  // Dump format: 'bin' = TLSD binary (dump_result_bin — ~10× smaller, parses
  // in a fraction of the JSON heap; needs the patched console_solver);
  // 'json' = the legacy JSON dump (the validation oracle; REQUIRED when
  // --emit-pack is on — explorer_pack still walks the JSON tree);
  // 'both' = one solve, both dumps (the WS1c equivalence harness).
  // Default 'json' until the dual-dump validation gate passes; flip to 'bin'
  // after (see the full-density cost plan, WS1c).
  var dumpFmt = (e['TLSOLVE_DUMP_FMT'] ?? 'json').toLowerCase();
  if (!const {'json', 'bin', 'both'}.contains(dumpFmt)) dumpFmt = 'json';
  return _SolveConfig(accuracy, maxIter, bets, timeoutS, threads, dumpFmt);
}

/// The current solve-config tag (for batch.dart's cache signature).
String solverConfigTag() => _config().tag;

/// Bet-size block.
/// 'single': one 50%-pot bet + all-in per street — fast, low branching (POC).
/// 'multi': TIERED for realism — flop (the decision we read) gets multiple sizes
/// + a raise; turn+river get a single size to bound the deep-tree explosion at
/// high SPR (keeps the deepest spots tractable / out of OOM territory).
/// 'turn': the FREQUENCY-LIBRARY turn-cell profile (DCE Q1 phase 2b). Same as
/// 'multi' on the flop, but the TURN also gets a raise + a second bet size so the
/// turn's GTO frequencies are FAITHFUL — without a turn raise the solver can't
/// check-raise and compensates by donk-leading the turn ~80% (the same distortion
/// 'vol' has on the flop), which would poison a turn frequency library. The RIVER
/// stays single-size + allin (cheap) — river cells aren't tabulated under this
/// profile (dump_rounds 2), so the deepest/branchiest layer is kept lean to bound
/// the tree. Costs more than 'multi' (the turn raise widens the tree); OOM risk at
/// medium SPR is measured by a calibration solve before the full grid.
/// 'river': the FREQUENCY-LIBRARY river-cell profile (DCE Q1 phase 2c). Same as
/// 'turn' on the flop+turn, but the RIVER ALSO gets a raise (+ allin) so river
/// frequencies are FAITHFUL — without a river raise the solver can't check-raise
/// the river and donk-leads it, the same distortion the lean river suffers. This
/// is the DEEPEST/branchiest tree (every street can check-raise) → solve it on a
/// big-RAM box; pair with dump_rounds 3 to tabulate the river street.
/// 'vol': board-VOLATILITY/sizing calibration — several bet sizes per street so
/// the GTO size CHOICE (vs texture) is observable, but NO raise/allin so the tree
/// stays tractable at deep single-raised SPR (~15) where 'multi' OOMs. 'single'
/// can't be used for sizing calibration (it offers only one size).
String _betSizes(String profile) {
  // Shared tiers so 'multi' and 'turn' define the flop/river ONCE (they differ
  // only on the turn). Flop tiered = the decision we read most; lean street =
  // single size + allin to bound tree depth.
  void flopTiered(StringBuffer b, String pos) {
    b.writeln('set_bet_sizes $pos,flop,bet,33,75');
    b.writeln('set_bet_sizes $pos,flop,raise,60');
    b.writeln('set_bet_sizes $pos,flop,allin');
  }

  void leanStreet(StringBuffer b, String pos, String street) {
    b.writeln('set_bet_sizes $pos,$street,bet,66');
    b.writeln('set_bet_sizes $pos,$street,allin');
  }

  // A street with ONE bet size + a raise (+ allin) → check-raise exists, so the
  // street's GTO frequencies are FAITHFUL. The single bet size (not two) keeps the
  // tree tractable; calibration showed a second size tripled cost / timed out.
  void raiseStreet(StringBuffer b, String pos, String street) {
    b.writeln('set_bet_sizes $pos,$street,bet,66');
    b.writeln('set_bet_sizes $pos,$street,raise,60');
    b.writeln('set_bet_sizes $pos,$street,allin');
  }

  final b = StringBuffer();
  for (final pos in ['oop', 'ip']) {
    if (profile == 'single') {
      for (final street in ['flop', 'turn', 'river']) {
        b.writeln('set_bet_sizes $pos,$street,bet,50');
        b.writeln('set_bet_sizes $pos,$street,allin');
      }
    } else if (profile == 'vol') {
      b.writeln('set_bet_sizes $pos,flop,bet,33,75');
      b.writeln('set_bet_sizes $pos,turn,bet,50,100');
      b.writeln('set_bet_sizes $pos,river,bet,75');
    } else if (profile == 'turn') {
      flopTiered(b, pos);
      raiseStreet(b, pos, 'turn'); // faithful turn (check-raise exists)
      leanStreet(b, pos, 'river'); // river not tabulated under 'turn'
    } else if (profile == 'river') {
      flopTiered(b, pos);
      raiseStreet(b, pos, 'turn'); // faithful turn
      raiseStreet(b, pos, 'river'); // faithful river (the deepest layer)
    } else {
      // 'multi': flop tiered; turn + river lean (no turn raise — v1).
      flopTiered(b, pos);
      leanStreet(b, pos, 'turn');
      leanStreet(b, pos, 'river');
    }
  }
  return b.toString();
}

String _buildInput(SolverSpot spot, String dumpPath, _SolveConfig cfg,
    {int dumpRounds = 1, String? betProfile}) {
  final profile = betProfile ?? cfg.betProfile;
  // Dump command(s) by format: 'both' emits the JSON and the TLSD binary from
  // the SAME converged strategy in one process — the WS1c equivalence harness
  // relies on this (two dumps of one solve, byte-comparable cells). The TLSD
  // sibling path is always "<jsonPath>.tlsd" by convention.
  final dumpCmds = switch (cfg.dumpFmt) {
    'bin' => 'dump_result_bin $dumpPath',
    'both' => 'dump_result $dumpPath\ndump_result_bin $dumpPath.tlsd',
    _ => 'dump_result $dumpPath',
  };
  return '''
set_pot ${spot.pot}
set_effective_stack ${spot.effStack}
set_board ${spot.board.join(',')}
set_range_ip ${spot.rangeIp}
set_range_oop ${spot.rangeOop}
${_betSizes(profile)}set_allin_threshold 0.67
build_tree
set_thread_num ${cfg.threads}
set_accuracy ${cfg.accuracy}
set_max_iteration ${cfg.maxIter}
set_print_interval 10
set_use_isomorphism 1
start_solve
set_dump_rounds $dumpRounds
$dumpCmds
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

/// The whole solved dump tree + run metadata, returned by [solveRoot]. Lets
/// callers walk to arbitrary nodes (the volatility batch reads range-aggregate
/// sizing and the turn chance node), rather than only hero's decision node.
class TreeSolveResult {
  final Map<String, dynamic> root;
  final double? exploitability;
  final int wallMs;
  TreeSolveResult(this.root, this.exploitability, this.wallMs);
}

class _RawSolve {
  final Map<String, dynamic> root;
  final double? exploitability;
  final int wallMs;
  _RawSolve(this.root, this.exploitability, this.wallMs);
}

/// Run the binary on [spot] and return the parsed dump root + exploitability +
/// wall time. Shared by [solve] (hero-node walk, dumpRounds 1) and [solveRoot]
/// (whole tree, dumpRounds 2). [dumpRounds] = 1 dumps the flop only, 2 adds the
/// turn nodes (needed to read the turn chance node's per-card children).
/// A solved dump left ON DISK for parsing elsewhere (typically a worker isolate,
/// so the heavy jsonDecode + tabulate runs off the main isolate). The caller OWNS
/// the temp dir and MUST call [cleanup] — it holds a multi-MB-to-multi-GB dump.
class DumpSolve {
  final String dumpPath;
  final double? exploitability;
  final int wallMs;
  final Directory _tmp;
  DumpSolve(this.dumpPath, this.exploitability, this.wallMs, this._tmp);
  void cleanup() {
    try {
      _tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

class _DumpRun {
  final String dumpPath;
  final String out; // captured solver stdout (for exploitability + verbose tail)
  final int wallMs;
  final Directory tmp;
  _DumpRun(this.dumpPath, this.out, this.wallMs, this.tmp);
}

/// Run the solver on [spot], leaving the dump ON DISK (no parse here). On ANY
/// failure the temp dir is removed and a StateError thrown; on SUCCESS the caller
/// owns [_DumpRun.tmp] and must delete it. The single source of the solver
/// invocation — both the parse-inline path ([_invokeSolver]) and the
/// parse-in-isolate path ([solveToFile]) build on it.
Future<_DumpRun> _runSolverToDump(SolverSpot spot, int dumpRounds,
    {String? betProfile}) async {
  final dir = _sourceDir();
  final bin = _solverBin(dir);
  if (!File(bin).existsSync()) {
    throw StateError('console_solver not found at $bin — build it first.');
  }
  // Log the resolved binary ONCE per run. _solverBin honors a TEXASSOLVER_BIN
  // override verbatim (needed for the Linux build path), so a stale env var could
  // point at an older solver and silently bake wrong frequencies into the shipped
  // library — surface the path so a wrong binary is visible in the log.
  if (!_loggedBin) {
    _loggedBin = true;
    stderr.writeln('[solver] using binary: $bin');
  }
  final tmp = Directory.systemTemp.createTempSync('tlsolve_');
  var keep = false; // hand tmp to the caller only on success
  try {
    final inputPath = '${tmp.path}/input.txt';
    final cfg = _config();
    // 'bin' writes only the TLSD file; 'json'/'both' keep the JSON as the
    // primary dumpPath ('both' adds the .tlsd sibling — see _buildInput).
    final dumpPath =
        cfg.dumpFmt == 'bin' ? '${tmp.path}/out.tlsd' : '${tmp.path}/out.json';
    File(inputPath).writeAsStringSync(_buildInput(spot, dumpPath, cfg,
        dumpRounds: dumpRounds, betProfile: betProfile));

    final sw = Stopwatch()..start();
    final proc = await Process.start(bin, ['-i', inputPath], workingDirectory: dir);
    final outF = proc.stdout.transform(utf8.decoder).join();
    final errF = proc.stderr.transform(utf8.decoder).join();
    final int exitCode;
    try {
      exitCode = await proc.exitCode.timeout(Duration(seconds: cfg.timeoutS));
    } on TimeoutException {
      proc.kill();
      throw StateError('solver timed out after ${cfg.timeoutS}s '
          '(spot too deep for the "${cfg.betProfile}" bet profile?)');
    }
    final out = await outF;
    final err = await errF;
    sw.stop();
    if (exitCode != 0) {
      throw StateError('solver exit $exitCode\n$err\n$out');
    }
    if (!File(dumpPath).existsSync()) {
      throw StateError('solver produced no output_result\n$out');
    }
    if (cfg.dumpFmt == 'both' && !File('$dumpPath.tlsd').existsSync()) {
      throw StateError('solver produced no TLSD sibling dump '
          '(dump_result_bin unsupported by this binary? rebuild it)\n$out');
    }
    keep = true;
    return _DumpRun(dumpPath, out, sw.elapsedMilliseconds, tmp);
  } finally {
    // Reclaim the temp dir on every FAILURE path (success hands it to the caller,
    // who deletes it). A long batch would otherwise accumulate dumps in %TEMP%.
    if (!keep) {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

Future<_RawSolve> _invokeSolver(
    SolverSpot spot, int dumpRounds, bool verbose,
    {String? betProfile}) async {
  final run = await _runSolverToDump(spot, dumpRounds, betProfile: betProfile);
  try {
    if (verbose) {
      stdout.writeln(run.out.split('\n').takeLast(4).join('\n'));
    }
    final root =
        jsonDecode(File(run.dumpPath).readAsStringSync()) as Map<String, dynamic>;
    return _RawSolve(root, _parseExploitability(run.out), run.wallMs);
  } finally {
    try {
      run.tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<SolveResult> solve(SolverSpot spot, {bool verbose = false}) async {
  final raw = await _invokeSolver(spot, 1, verbose);
  var node = raw.root;
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
    exploitability: raw.exploitability,
    wallMs: raw.wallMs,
    nodePlayer: node['player'] as int?,
  );
}

/// Solve [spot] and return the whole dump tree (default dumpRounds 2 → flop+turn)
/// for free-form node walking. Used by the volatility calibration batch.
Future<TreeSolveResult> solveRoot(SolverSpot spot,
    {int dumpRounds = 2, bool verbose = false, String? betProfile}) async {
  final raw = await _invokeSolver(spot, dumpRounds, verbose, betProfile: betProfile);
  return TreeSolveResult(raw.root, raw.exploitability, raw.wallMs);
}

/// Solve [spot] and leave the dump ON DISK without parsing it — for callers that
/// run the heavy parse + tabulate in a worker isolate (`tabulateDumpFile`), so the
/// big jsonDecode + tree walk don't block the main isolate. On river dumps that
/// walk dominates wall time and serialized on the single isolate; this lets
/// `--parallel` workers tabulate on separate cores. The caller MUST call
/// [DumpSolve.cleanup] once it has tabulated (or on failure).
Future<DumpSolve> solveToFile(SolverSpot spot,
    {int dumpRounds = 2, String? betProfile}) async {
  final run = await _runSolverToDump(spot, dumpRounds, betProfile: betProfile);
  return DumpSolve(run.dumpPath, _parseExploitability(run.out), run.wallMs, run.tmp);
}

/// Follow a sequence of child keys from [node] — case- and "BET x"-prefix-
/// tolerant exactly like [solve]'s heroPath walk, so action steps ("CHECK") and
/// turn cards ("2c") both resolve. Returns null if any step is missing (the
/// caller decides whether that's fatal).
Map<String, dynamic>? followChildren(
    Map<String, dynamic> node, List<String> steps) {
  var cur = node;
  for (final step in steps) {
    final children = cur['childrens'] as Map<String, dynamic>?;
    if (children == null) return null;
    final key = children.keys.firstWhere(
      (k) => k == step || k.toUpperCase().startsWith(step.toUpperCase()),
      orElse: () => '',
    );
    if (key.isEmpty) return null;
    cur = children[key] as Map<String, dynamic>;
  }
  return cur;
}

/// Range-aggregate action distribution at an action node: each action's MEAN
/// strategy frequency across all combos present in the node (uniform combo
/// weight — the GTO preset ranges are unweighted, so this ≈ range-weighted).
/// Returns the action labels aligned to the mean frequencies, or null if the
/// node has no per-combo strategy (chance/terminal node).
({List<String> actions, List<double> freqs})? nodeAggregateStrategy(
    Map<String, dynamic> node) {
  final strat = node['strategy'] as Map<String, dynamic>?;
  if (strat == null) return null;
  final actions = (strat['actions'] as List).cast<String>();
  final byCombo = strat['strategy'] as Map<String, dynamic>?;
  if (byCombo == null || byCombo.isEmpty) return null;
  final sums = List<double>.filled(actions.length, 0.0);
  var n = 0;
  for (final v in byCombo.values) {
    if (v is! List) continue;
    for (var i = 0; i < actions.length && i < v.length; i++) {
      sums[i] += (v[i] as num).toDouble();
    }
    n++;
  }
  if (n == 0) return null;
  return (actions: actions, freqs: [for (final s in sums) s / n]);
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int n) {
    final l = toList();
    return l.sublist(l.length - n < 0 ? 0 : l.length - n);
  }
}
