// Variance-calculator math (pure Dart — no Flutter imports, mirrors the
// lib/equity/ discipline so it unit-tests under plain `dart test` and its
// Monte Carlo can run in a compute() isolate).
//
// UNIT NORMALIZATION — everything below works in abstract "units":
//   Cash:        1 unit = 100 hands. meanPerUnit = winrate (bb/100),
//                sdPerUnit = SD (bb/100), units = hands/100, bankroll in bb.
//   Tournaments: 1 unit = 1 tournament. meanPerUnit = ROI/100 (profit in
//                buy-ins per tournament), sdPerUnit = SD (buy-ins),
//                units = # tournaments, bankroll in buy-ins.
//
// The classic risk-of-ruin formula RoR = exp(−2·μ·B/σ²) is UNIT-INVARIANT
// under this normalization: with per-hand μ = WR/100 and per-hand variance
// σ²_hand = SD²/100, exp(−2·(WR/100)·B/(SD²/100)) = exp(−2·WR·B/SD²) — the
// 100s cancel, so feeding bb/100 figures directly is correct (and trivially
// so in tournament units).
//
// CAVEAT (surfaced in UI copy, not here): all of this is the normal
// approximation of a random walk with drift. Tournament result distributions
// are heavily right-skewed, so tournament RoR/bands UNDERSTATE tail risk at
// small sample sizes — treat as estimates.

import 'dart:math' as math;

/// Two-sided z for a 70% interval (Φ⁻¹(0.85)).
const double z70 = 1.0364334;

/// Two-sided z for a 95% interval (Φ⁻¹(0.975)).
const double z95 = 1.9599640;

/// Standard normal CDF via the Abramowitz–Stegun 7.1.26 erf approximation
/// (|ε| < 1.5e-7 — far below display precision).
double normalCdf(double z) {
  final x = z / math.sqrt2;
  final ax = x.abs();
  final t = 1.0 / (1.0 + 0.3275911 * ax);
  final poly = t *
      (0.254829592 +
          t *
              (-0.284496736 +
                  t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  final erf = 1.0 - poly * math.exp(-ax * ax);
  final signedErf = x >= 0 ? erf : -erf;
  return 0.5 * (1.0 + signedErf);
}

class VarianceResult {
  /// Expected result after [unit count] units (bb or buy-ins).
  final double ev;

  /// Standard deviation of the total result at the horizon.
  final double sd;

  final double ci70Low, ci70High;
  final double ci95Low, ci95High;

  /// Probability the total result after the horizon is below zero.
  final double pLoss;

  /// Probability of ever going broke with the given bankroll while playing
  /// at this winrate forever (classic drift formula). Null when no bankroll
  /// was supplied; 1.0 when the winrate is ≤ 0 (a non-winner always busts
  /// eventually).
  final double? riskOfRuin;

  /// Bankroll needed to cap risk of ruin at 5% / 1%. Null when winrate ≤ 0
  /// (no finite bankroll suffices).
  final double? bankrollForRoR5;
  final double? bankrollForRoR1;

  const VarianceResult({
    required this.ev,
    required this.sd,
    required this.ci70Low,
    required this.ci70High,
    required this.ci95Low,
    required this.ci95High,
    required this.pLoss,
    this.riskOfRuin,
    this.bankrollForRoR5,
    this.bankrollForRoR1,
  });
}

/// Closed-form variance outputs for a horizon of [units] units.
VarianceResult computeVariance({
  required double meanPerUnit,
  required double sdPerUnit,
  required double units,
  double? bankroll,
}) {
  final ev = meanPerUnit * units;
  final sd = sdPerUnit * math.sqrt(units);

  final pLoss = sd > 0 ? normalCdf(-ev / sd) : (ev < 0 ? 1.0 : 0.0);

  double? ror;
  if (bankroll != null) {
    if (meanPerUnit <= 0) {
      ror = 1.0;
    } else if (sdPerUnit <= 0) {
      ror = 0.0;
    } else {
      ror = math
          .exp(-2 * meanPerUnit * bankroll / (sdPerUnit * sdPerUnit))
          .clamp(0.0, 1.0);
    }
  }

  double? minBankroll(double r) {
    if (meanPerUnit <= 0 || sdPerUnit <= 0) return meanPerUnit <= 0 ? null : 0;
    return sdPerUnit * sdPerUnit * math.log(1 / r) / (2 * meanPerUnit);
  }

  return VarianceResult(
    ev: ev,
    sd: sd,
    ci70Low: ev - z70 * sd,
    ci70High: ev + z70 * sd,
    ci95Low: ev - z95 * sd,
    ci95High: ev + z95 * sd,
    pLoss: pLoss,
    riskOfRuin: ror,
    bankrollForRoR5: minBankroll(0.05),
    bankrollForRoR1: minBankroll(0.01),
  );
}

/// One standard normal draw via Box–Muller (two uniforms → one normal; the
/// second is discarded for simplicity — path counts here are tiny).
double _gauss(math.Random rng) {
  // Guard u1 > 0 so log() stays finite.
  final u1 = rng.nextDouble().clamp(1e-12, 1.0);
  final u2 = rng.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

/// Seeded sample paths for the chart: paths[i][k] = cumulative result after
/// step k (k = 0..steps, starting at 0). Deterministic per [seed] — identical
/// inputs render identical curves (the app's seeded-visual convention); bump
/// the seed to "reroll".
List<List<double>> simulatePaths({
  required double meanPerUnit,
  required double sdPerUnit,
  required double units,
  int paths = 20,
  int steps = 120,
  required int seed,
}) {
  final rng = math.Random(seed);
  final h = units / steps;
  final drift = meanPerUnit * h;
  final vol = sdPerUnit * math.sqrt(h);
  return List.generate(paths, (_) {
    final p = List<double>.filled(steps + 1, 0);
    for (var k = 1; k <= steps; k++) {
      p[k] = p[k - 1] + drift + vol * _gauss(rng);
    }
    return p;
  });
}

/// Parameter object for [simulateDownswings] — one argument so the function
/// can run through Flutter's compute() (isolate entry points take a single
/// message).
class DownswingParams {
  final double meanPerUnit;
  final double sdPerUnit;
  final double units;
  final double? bankroll;
  final int trials;
  final int steps;
  final int seed;

  const DownswingParams({
    required this.meanPerUnit,
    required this.sdPerUnit,
    required this.units,
    this.bankroll,
    this.trials = 2000,
    this.steps = 200,
    required this.seed,
  });
}

class DownswingStats {
  /// Median / 95th-percentile MAXIMUM DRAWDOWN (peak-to-trough) over the
  /// horizon, in units' result terms (bb or buy-ins).
  final double medianMaxDrawdown;
  final double p95MaxDrawdown;

  /// Fraction of trials whose max drawdown reached the bankroll (i.e. would
  /// have gone broke DURING the horizon). Null when no bankroll given.
  final double? pDrawdownExceedsBankroll;

  const DownswingStats({
    required this.medianMaxDrawdown,
    required this.p95MaxDrawdown,
    this.pDrawdownExceedsBankroll,
  });
}

/// Monte Carlo max-drawdown distribution — TOP-LEVEL so it can be handed to
/// compute(). Deterministic per seed.
DownswingStats simulateDownswings(DownswingParams p) {
  final rng = math.Random(p.seed);
  final h = p.units / p.steps;
  final drift = p.meanPerUnit * h;
  final vol = p.sdPerUnit * math.sqrt(h);

  final maxDrawdowns = List<double>.filled(p.trials, 0);
  var busts = 0;
  for (var t = 0; t < p.trials; t++) {
    var x = 0.0, peak = 0.0, maxDd = 0.0;
    for (var k = 0; k < p.steps; k++) {
      x += drift + vol * _gauss(rng);
      if (x > peak) peak = x;
      final dd = peak - x;
      if (dd > maxDd) maxDd = dd;
    }
    maxDrawdowns[t] = maxDd;
    if (p.bankroll != null && maxDd >= p.bankroll!) busts++;
  }
  maxDrawdowns.sort();
  double q(double frac) =>
      maxDrawdowns[(frac * (p.trials - 1)).round().clamp(0, p.trials - 1)];
  return DownswingStats(
    medianMaxDrawdown: q(0.5),
    p95MaxDrawdown: q(0.95),
    pDrawdownExceedsBankroll:
        p.bankroll == null ? null : busts / p.trials,
  );
}
