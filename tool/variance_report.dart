// Reproducible figure generator for the blog post
// "Poker Tournament Variance: How Big a Sample Before Your ROI Means Anything?"
//
// Runs the app's OWN variance engine (lib/utils/variance_math.dart — the same
// code behind /variance-calculator and the in-app Variance tool) so every number
// published in the article is reproducible by a reader.
//
//   dart run tool/variance_report.dart
//
// Tournament unit convention (see variance_math.dart header):
//   1 unit = 1 tournament, meanPerUnit = ROI as a fraction (20% -> 0.20),
//   sdPerUnit = SD in buy-ins, bankroll in buy-ins.

import 'dart:io';
import 'dart:math' as math;

import 'package:tablelab/utils/variance_math.dart';

/// Frozen so the published figures reproduce exactly.
const int kSeed = 20260803;

/// Closed-form tables are free, so they sweep the full grid.
/// The Monte Carlo tables are O(trials x steps) per cell, so they run on a
/// trimmed grid at a trial count that still gives a stable 95th percentile.
const int kTrials = 20000;
const int kSteps = 200;

const List<int> kSamples = [50, 200, 500, 1000, 2000, 5000];
const List<double> kRois = [0.10, 0.20, 0.30];

/// SD per tournament, in buy-ins, by field size.
///
/// These are NOT free parameters and NOT looked up: tournament SD is a
/// CONSEQUENCE of field size and payout shape. Primedope's tournament
/// calculator takes no SD input at all — it derives variance by Monte Carlo
/// from the structure. The ladder below is back-derived from published
/// simulation OUTPUTS (SD_total / sqrt(N) / buy-in):
///
///   100 runners  -> 3.7 BI   (Anttonen / Upswing, 30% ROI, N=1000)
///   300 runners  -> 6.1 BI   (O'Kearney & Carter via Tendler, 25% ROI, N=520)
///   2,000        -> 12.0 BI  (Anttonen / Upswing, 30% ROI, N=1000)
///   7,000        -> 33.7 BI  (O'Kearney & Carter via Tendler, 25% ROI, N=520)
///
/// SD scales roughly with the SQUARE ROOT of field size (fitted exponent
/// k ~ 0.40-0.55 across both sources), which interpolates to ~10-12 BI at
/// 1,000 runners. Both source chains trace to the SAME upstream tool, so
/// this is one methodology, not two independent measurements — and it is
/// simulation-derived, not measured from a real results database.
const List<double> kSds = [3.7, 6.1, 10.0, 12.0, 20.0, 33.7];

/// Trimmed grids for the simulated tables: small / mid / very large field.
const List<double> kMcSds = [6.1, 12.0, 33.7];
const List<double> kMcRois = [0.20];

String pct(double v, {int dp = 1}) => '${(v * 100).toStringAsFixed(dp)}%';
String bi(double v, {int dp = 1}) => '${v.toStringAsFixed(dp)} BI';

void main() {
  stdout.writeln('=' * 78);
  stdout.writeln('TABLELAB — TOURNAMENT VARIANCE REPORT');
  stdout.writeln('engine: lib/utils/variance_math.dart   seed: $kSeed');
  stdout.writeln('trials: $kTrials   steps: $kSteps');
  stdout.writeln('=' * 78);

  // ---------------------------------------------------------------------
  // TABLE 1 — measured-ROI confidence band vs sample size.
  // The headline: after N tournaments, what range could your OBSERVED ROI
  // land in when your TRUE ROI is fixed?
  // ---------------------------------------------------------------------
  for (final roi in kRois) {
    stdout.writeln('\n\nTABLE 1 — observed ROI band, true ROI = ${pct(roi, dp: 0)}');
    stdout.writeln('(95% of the time your measured ROI lands inside this band)');
    stdout.writeln('-' * 78);
    stdout.writeln('${'SD'.padRight(8)}${'N'.padLeft(6)}'
        '${'obs ROI low'.padLeft(14)}${'obs ROI high'.padLeft(14)}'
        '${'band width'.padLeft(13)}${'P(losing)'.padLeft(12)}');
    stdout.writeln('-' * 78);
    for (final sd in kSds) {
      for (final n in kSamples) {
        final r = computeVariance(
          meanPerUnit: roi,
          sdPerUnit: sd,
          units: n.toDouble(),
        );
        // Convert the TOTAL-result band into an observed-ROI-per-tournament band.
        final lo = r.ci95Low / n;
        final hi = r.ci95High / n;
        stdout.writeln('${bi(sd).padRight(8)}${n.toString().padLeft(6)}'
            '${pct(lo).padLeft(14)}${pct(hi).padLeft(14)}'
            '${pct(hi - lo).padLeft(13)}${pct(r.pLoss).padLeft(12)}');
      }
      stdout.writeln('');
    }
  }

  // ---------------------------------------------------------------------
  // TABLE 2 — how many tournaments to pin the observed ROI within +/- 5pt
  // and +/- 2pt of truth (95% confidence). Solved directly, not searched:
  //   halfWidth = z95 * sd / sqrt(N)  ->  N = (z95 * sd / halfWidth)^2
  // ---------------------------------------------------------------------
  stdout.writeln('\n\nTABLE 2 — sample needed to pin observed ROI near the true ROI');
  stdout.writeln('(95% confidence; independent of the true ROI itself)');
  stdout.writeln('-' * 78);
  stdout.writeln('${'SD'.padRight(10)}${'+/-10pt'.padLeft(14)}${'+/-5pt'.padLeft(14)}'
      '${'+/-2pt'.padLeft(14)}${'+/-1pt'.padLeft(14)}');
  stdout.writeln('-' * 78);
  for (final sd in kSds) {
    String need(double halfWidth) {
      final n = math.pow(z95 * sd / halfWidth, 2).ceil();
      return _thousands(n);
    }

    stdout.writeln('${bi(sd).padRight(10)}${need(0.10).padLeft(14)}'
        '${need(0.05).padLeft(14)}${need(0.02).padLeft(14)}'
        '${need(0.01).padLeft(14)}');
  }

  // ---------------------------------------------------------------------
  // TABLE 3 — Monte Carlo max drawdown (peak-to-trough), in buy-ins.
  // This is what a "normal" downswing actually looks like for a WINNER.
  // ---------------------------------------------------------------------
  for (final roi in kMcRois) {
    stdout.writeln('\n\nTABLE 3 — max drawdown over N tournaments, true ROI = '
        '${pct(roi, dp: 0)}');
    stdout.writeln('(peak-to-trough, in buy-ins; $kTrials simulated careers)');
    stdout.writeln('-' * 78);
    stdout.writeln('${'SD'.padRight(8)}${'N'.padLeft(6)}'
        '${'median DD'.padLeft(14)}${'95th pct DD'.padLeft(14)}'
        '${'median @200st'.padLeft(16)}');
    stdout.writeln('-' * 78);
    for (final sd in kMcSds) {
      for (final n in kSamples) {
        // steps == units: ONE step per tournament. A coarser grid aggregates
        // several tournaments into a single increment and therefore misses
        // intra-block troughs, understating max drawdown. Granularity matters
        // here in a way it does not for the closed-form tables.
        final d = simulateDownswings(DownswingParams(
          meanPerUnit: roi,
          sdPerUnit: sd,
          units: n.toDouble(),
          trials: kTrials,
          steps: n,
          seed: kSeed,
        ));
        // Same cell on the old coarse grid, to quantify the understatement.
        final coarse = simulateDownswings(DownswingParams(
          meanPerUnit: roi,
          sdPerUnit: sd,
          units: n.toDouble(),
          trials: kTrials,
          steps: kSteps,
          seed: kSeed,
        ));
        stdout.writeln('${bi(sd).padRight(8)}${n.toString().padLeft(6)}'
            '${bi(d.medianMaxDrawdown).padLeft(14)}'
            '${bi(d.p95MaxDrawdown).padLeft(14)}'
            '${bi(coarse.medianMaxDrawdown).padLeft(16)}');
      }
      stdout.writeln('');
    }
  }

  // ---------------------------------------------------------------------
  // TABLE 4 — bankroll required to hold risk of ruin at 5% / 1%.
  // Closed form, so it is exact rather than simulated.
  // ---------------------------------------------------------------------
  stdout.writeln('\n\nTABLE 4 — bankroll needed to cap risk of ruin (buy-ins)');
  stdout.writeln('-' * 78);
  stdout.writeln('${'SD'.padRight(10)}${'ROI'.padLeft(8)}'
      '${'RoR <= 5%'.padLeft(14)}${'RoR <= 1%'.padLeft(14)}');
  stdout.writeln('-' * 78);
  for (final sd in kSds) {
    for (final roi in kRois) {
      final r = computeVariance(
        meanPerUnit: roi,
        sdPerUnit: sd,
        units: 1000,
      );
      stdout.writeln('${bi(sd).padRight(10)}${pct(roi, dp: 0).padLeft(8)}'
          '${bi(r.bankrollForRoR5!, dp: 0).padLeft(14)}'
          '${bi(r.bankrollForRoR1!, dp: 0).padLeft(14)}');
    }
    stdout.writeln('');
  }

  // ---------------------------------------------------------------------
  // TABLE 5 — in-horizon bust probability at realistic bankrolls.
  // ---------------------------------------------------------------------
  stdout.writeln('\n\nTABLE 5 — chance of busting a fixed bankroll within 1,000 events');
  stdout.writeln('(true ROI = 20%; $kTrials simulated careers)');
  stdout.writeln('-' * 78);
  stdout.writeln('${'SD'.padRight(10)}${'roll=50BI'.padLeft(12)}'
      '${'roll=100BI'.padLeft(12)}${'roll=200BI'.padLeft(12)}'
      '${'roll=500BI'.padLeft(12)}');
  stdout.writeln('-' * 78);
  for (final sd in kMcSds) {
    final cells = <String>[];
    for (final roll in [50.0, 100.0, 200.0, 500.0]) {
      final d = simulateDownswings(DownswingParams(
        meanPerUnit: 0.20,
        sdPerUnit: sd,
        units: 1000,
        bankroll: roll,
        trials: kTrials,
        steps: kSteps,
        seed: kSeed,
      ));
      cells.add(pct(d.pBustDuringHorizon!).padLeft(12));
    }
    stdout.writeln('${bi(sd).padRight(10)}${cells.join()}');
  }

  // ---------------------------------------------------------------------
  // TABLE 6 — EXTERNAL COMPARISON.
  // Re-run the published scenarios from O'Kearney & Carter (Endgame Poker
  // Strategy, via jaredtendler.com) and Anttonen (Upswing) through OUR engine.
  //
  // READ THE LIMITS BEFORE QUOTING THIS AS VALIDATION:
  //  1. SD_total agreement is CIRCULAR. The sdPerUnit inputs below were
  //     back-derived from those same published totals, so the standard
  //     deviations must agree — that reproduces our arithmetic, nothing more.
  //     Only the PROBABILITIES (risk of ruin, P(loss)) are actually tested.
  //  2. Their figures come from a different tool, but a single one (the
  //     Primedope tournament simulator). This tests calibration against one
  //     structure-aware implementation, NOT against reality.
  //  3. The scenarios use their own ROI/N, not the 20% / 1,000 used elsewhere
  //     in this report. Do not read the rows as continuous with Tables 1-5.
  //
  // Their published scenarios:
  //   Sunday Million  7,000 runners, $109, ROI 25%, N=520, roll $10,000
  //                   -> SD $83,632 total, risk of ruin 86.5%, P(loss) 56.9%
  //   SuperNova         300 runners, EUR109, ROI 25%, N=520, roll $10,000
  //                   -> SD $15,115 total, risk of ruin 15.1%, P(loss) 17.3%
  //   Anttonen        2,000 runners, $22, ROI 30%, N=1,000
  //                   -> P(losing money) 23%
  // ---------------------------------------------------------------------
  stdout.writeln('\n\nTABLE 6 — external validation vs published figures');
  stdout.writeln('(their numbers come from a DIFFERENT simulator; ours from '
      'variance_math.dart)');
  stdout.writeln('-' * 78);

  void validate({
    required String label,
    required double roi,
    required double sd,
    required int n,
    required double buyIn,
    required double rollCash,
    required String published,
  }) {
    final rollBi = rollCash / buyIn;
    final r = computeVariance(
      meanPerUnit: roi,
      sdPerUnit: sd,
      units: n.toDouble(),
      bankroll: rollBi,
    );
    final d = simulateDownswings(DownswingParams(
      meanPerUnit: roi,
      sdPerUnit: sd,
      units: n.toDouble(),
      bankroll: rollBi,
      trials: kTrials,
      steps: kSteps,
      seed: kSeed,
    ));
    stdout.writeln('\n$label');
    stdout.writeln('  inputs: ROI ${pct(roi, dp: 0)}, SD ${bi(sd)}, '
        'N=$n, roll ${rollBi.toStringAsFixed(1)} BI');
    stdout.writeln('  published : $published');
    stdout.writeln('  ours      : SD_total \$${(r.sd * buyIn).round()}, '
        'RoR(forever) ${pct(r.riskOfRuin!)}, '
        'bust-in-horizon ${pct(d.pBustDuringHorizon!)}, '
        'P(loss) ${pct(r.pLoss)}');
  }

  validate(
    label: "Sunday Million (7,000 runners) — O'Kearney & Carter",
    roi: 0.25,
    sd: 33.7,
    n: 520,
    buyIn: 109,
    rollCash: 10000,
    published: r'SD_total $83,632, RoR 86.5%, P(loss) 56.9%',
  );
  validate(
    label: "SuperNova (300 runners) — O'Kearney & Carter",
    roi: 0.25,
    sd: 6.1,
    n: 520,
    buyIn: 109,
    rollCash: 10000,
    published: r'SD_total $15,115, RoR 15.1%, P(loss) 17.3%',
  );
  validate(
    label: 'Large field (2,000 runners) — Anttonen / Upswing',
    roi: 0.30,
    sd: 12.0,
    n: 1000,
    buyIn: 22,
    rollCash: 11000,
    published: r'SD_total $8,378, P(losing money) 23%',
  );

  stdout.writeln('\n${'=' * 78}');
  stdout.writeln('NOTE: all of the above is the NORMAL APPROXIMATION of a random walk');
  stdout.writeln('with drift. Real tournament results are heavily right-skewed, so');
  stdout.writeln('these bands and ruin figures UNDERSTATE true tail risk at small');
  stdout.writeln('sample sizes. See the caveat in variance_math.dart:18-21.');
  stdout.writeln('=' * 78);
}

String _thousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
