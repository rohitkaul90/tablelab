// RAM-aware spot scheduler (full-density cost plan WS2).
//
// The grid's old fixed `--parallel N` sized concurrency for the WORST spot
// class: deep-river spots need ~90 GB to solve (and, pre-TLSD, ~150 GB to
// parse), so N was set to ~5 on a 1 TB box and the 128 cores ran ~16% busy
// while shallow/3bp spots — which need a few GB — queued behind the same cap.
//
// This replaces the cap with an ADMISSION CONTROLLER over two resources
// (RAM GB, CPU threads): each spot declares a predicted footprint per phase
// (solve: TLSOLVE_THREADS threads + class RAM; parse: 1 thread + small RAM),
// and starts as soon as both fit. Pending spots are pre-sorted LONGEST FIRST
// (LPT) so the deep tails start early and shallow spots backfill around them —
// the observed "last deep spot runs alone for 20 minutes" idle is exactly what
// LPT removes.
//
// Budgets:
//   TLSOLVE_RAM_BUDGET_GB — default: MemTotal × 0.85 (/proc/meminfo, Linux
//     boxes); 48 GB fallback where meminfo is unavailable (Windows dev runs).
//     The 15% margin also covers dump bytes on a /dev/shm TMPDIR.
//   TLSOLVE_CPU_BUDGET   — default: Platform.numberOfProcessors ×
//     TLSOLVE_CPU_OVERSUB.
//   TLSOLVE_CPU_OVERSUB  — core-count multiplier (default 1.0), ignored when
//     TLSOLVE_CPU_BUDGET is set explicitly. The solver CLAIMS 8 threads but
//     effectively drives ~4-5 (calibration measured ~50-55% CPU util on both
//     box classes), so 1.5-2.0 packs more concurrent solves onto the same
//     cores. RAM claims still gate the deep class, so oversubscription mainly
//     lets shallow/medium backfill harder.
//   TLSOLVE_MAX_SPOT_GB  — SKIP (not fail) spots whose predicted solve RAM
//     exceeds it: lets a small-RAM box (e.g. a 256 GB Hetzner) grind the
//     shallow/medium classes while a big box handles deep — pure env policy.
//
// Footprints are a static, measured-informed table (river profile, 8 threads)
// with a deliberate lean toward OVER-estimating: a wrong table under-packs
// (slower), never OOMs. Refine from observed peaks as bulk cycles land.

import 'dart:async';
import 'dart:io';

/// Parses the TLSOLVE_SPRS include-filter: a comma list of SPR bucket NAMES
/// (e.g. "deep" or "shallow,medium"), trimmed and lowercased. Returns null for
/// an unset/empty value (= no filter). Throws [StateError] on any name not in
/// [validBuckets] — bucket sets differ per scenario (3bp has
/// committed/shallow/medium and NO deep), so a typo'd or wrong-scenario filter
/// must fail fast rather than silently solving zero spots.
Set<String>? parseSprFilter(String? env, Iterable<String> validBuckets) {
  final raw = (env ?? '').trim();
  if (raw.isEmpty) return null;
  final valid = validBuckets.toSet();
  final names = raw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();
  if (names.isEmpty) return null;
  final unknown = names.difference(valid);
  if (unknown.isNotEmpty) {
    throw StateError('unknown SPR bucket(s) ${unknown.join(',')} — this '
        'scenario has: ${valid.join(',')}');
  }
  return names;
}

/// Predicted per-phase resource footprint of one spot.
class SpotFootprint {
  final double solveGb;
  final double parseGb;
  final double estMinutes; // LPT ordering only — not a resource

  const SpotFootprint({
    required this.solveGb,
    required this.parseGb,
    required this.estMinutes,
  });
}

/// Footprint for a spot at [sprVal] under [dumpFmt] ('bin'|'json'|'both').
/// Buckets by SPR value (the tree-size driver), NOT by the scenario's SPR
/// *name* — 3bp "medium" is SPR 4 while srp "medium" is SPR 6, and what the
/// solver cares about is the tree, so the value is the honest key.
///
/// Solve RAM: measured deep-river solve peaked ~89 GB (srp_late, 8t); medium
/// ~26-32 GB; shallow and 3-bet-pot trees far smaller. Parse RAM: a TLSD dump
/// decodes to a typed tree at ~2-3× its raw bytes (deep ~1-2 GB raw); the
/// JSON path needs the giant jsonDecode heap (deep ~150 GB — the pre-WS1
/// bottleneck, kept here so a JSON bulk run still packs safely).
SpotFootprint spotFootprint(double sprVal, {required String dumpFmt}) {
  final bool json = dumpFmt != 'bin'; // 'both' pays the JSON parse too
  if (sprVal >= 10) {
    return SpotFootprint(
        solveGb: 100, parseGb: json ? 160 : 8, estMinutes: 18);
  }
  if (sprVal >= 5) {
    return SpotFootprint(solveGb: 36, parseGb: json ? 45 : 4, estMinutes: 6);
  }
  if (sprVal >= 2.5) {
    return SpotFootprint(solveGb: 16, parseGb: json ? 12 : 2, estMinutes: 2.5);
  }
  return SpotFootprint(solveGb: 8, parseGb: json ? 6 : 1, estMinutes: 1);
}

/// Async admission controller over (RAM GB, CPU threads). Single-isolate:
/// acquire/release run synchronously between awaits, so state mutations are
/// atomic w.r.t. the grid's workers. First-fit with skip-ahead: a small claim
/// may pass a blocked large one (LPT ordering starts the large ones first, so
/// this backfills rather than starves).
class ResourceBudget {
  double _gbFree;
  int _threadsFree;
  final double totalGb;
  final int totalThreads;
  final _waiters = <_Claim>[];

  ResourceBudget({required this.totalGb, required this.totalThreads})
      : _gbFree = totalGb,
        _threadsFree = totalThreads;

  /// Env-configured budget (see the header comment).
  factory ResourceBudget.fromEnv() {
    final env = Platform.environment;
    final gb = double.tryParse(env['TLSOLVE_RAM_BUDGET_GB'] ?? '') ??
        _autoRamBudgetGb();
    final oversub =
        double.tryParse(env['TLSOLVE_CPU_OVERSUB'] ?? '') ?? 1.0;
    final threads = int.tryParse(env['TLSOLVE_CPU_BUDGET'] ?? '') ??
        (Platform.numberOfProcessors * oversub).round();
    return ResourceBudget(totalGb: gb, totalThreads: threads);
  }

  static double _autoRamBudgetGb() {
    try {
      final meminfo = File('/proc/meminfo');
      if (meminfo.existsSync()) {
        final m = RegExp(r'MemTotal:\s+(\d+) kB')
            .firstMatch(meminfo.readAsStringSync());
        if (m != null) {
          return int.parse(m.group(1)!) / 1024 / 1024 * 0.85;
        }
      }
    } catch (_) {}
    return 48; // conservative Windows-dev fallback; boxes set the env var
  }

  double get gbFree => _gbFree;
  int get threadsFree => _threadsFree;

  /// Acquire [gb] + [threads], waiting until they fit. A claim larger than
  /// the whole budget is clamped (with a warning) — it runs ALONE rather than
  /// deadlocking; TLSOLVE_MAX_SPOT_GB is the way to exclude such spots.
  Future<void> acquire(double gb, int threads) {
    var g = gb;
    var t = threads;
    if (g > totalGb) {
      stderr.writeln('WARN spot_sched: claim ${g.toStringAsFixed(0)} GB > '
          'budget ${totalGb.toStringAsFixed(0)} GB — clamping (runs alone).');
      g = totalGb;
    }
    if (t > totalThreads) t = totalThreads;
    if (_waiters.isEmpty && _fits(g, t)) {
      _take(g, t);
      return Future.value();
    }
    final c = _Claim(g, t);
    _waiters.add(c);
    return c.completer.future;
  }

  void release(double gb, int threads) {
    _gbFree += gb;
    _threadsFree += threads;
    // Clamp against drift from clamped claims.
    if (_gbFree > totalGb) _gbFree = totalGb;
    if (_threadsFree > totalThreads) _threadsFree = totalThreads;
    _pump();
  }

  bool _fits(double gb, int threads) =>
      gb <= _gbFree + 1e-9 && threads <= _threadsFree;

  void _take(double gb, int threads) {
    _gbFree -= gb;
    _threadsFree -= threads;
  }

  void _pump() {
    var i = 0;
    while (i < _waiters.length) {
      final c = _waiters[i];
      if (_fits(c.gb, c.threads)) {
        _take(c.gb, c.threads);
        _waiters.removeAt(i);
        c.completer.complete();
      } else {
        i++;
      }
    }
  }
}

class _Claim {
  final double gb;
  final int threads;
  final completer = Completer<void>();
  _Claim(this.gb, this.threads);
}
