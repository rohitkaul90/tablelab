import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/utils/variance_math.dart';

void main() {
  group('normalCdf', () {
    test('matches standard normal table values', () {
      expect(normalCdf(0), closeTo(0.5, 1e-7));
      expect(normalCdf(1), closeTo(0.8413447, 1e-4));
      expect(normalCdf(1.96), closeTo(0.9750021, 1e-4));
      expect(normalCdf(-1), closeTo(0.1586553, 1e-4));
      expect(normalCdf(-3), closeTo(0.0013499, 1e-5));
    });
  });

  group('computeVariance — cash worked example', () {
    // WR 5 bb/100, SD 90 bb/100, 10,000 hands → U = 100 units.
    final r = computeVariance(
        meanPerUnit: 5, sdPerUnit: 90, units: 100, bankroll: 2000);

    test('EV and horizon SD', () {
      expect(r.ev, closeTo(500, 1e-9));
      expect(r.sd, closeTo(900, 1e-9));
    });

    test('95% band', () {
      expect(r.ci95Low, closeTo(500 - 1.9599640 * 900, 1e-3));
      expect(r.ci95High, closeTo(500 + 1.9599640 * 900, 1e-3));
    });

    test('P(loss) = Φ(−EV/σ)', () {
      // Φ(−0.5556) ≈ 0.2893
      expect(r.pLoss, closeTo(0.2893, 5e-4));
    });

    test('risk of ruin with a 2,000 bb bankroll', () {
      // exp(−2·5·2000/8100) ≈ 0.08466
      expect(r.riskOfRuin, closeTo(0.08466, 5e-4));
    });

    test('min bankroll for 5% / 1% RoR', () {
      // σ²·ln(1/r)/(2μ): 810·ln20 ≈ 2426.6 ; 810·ln100 ≈ 3730.2
      expect(r.bankrollForRoR5, closeTo(2426.6, 0.5));
      expect(r.bankrollForRoR1, closeTo(3730.2, 0.5));
    });

    test('round trip: RoR at the min-bankroll ≈ the target', () {
      final ror5 = computeVariance(
              meanPerUnit: 5,
              sdPerUnit: 90,
              units: 100,
              bankroll: r.bankrollForRoR5)
          .riskOfRuin;
      expect(ror5, closeTo(0.05, 1e-6));
    });
  });

  group('computeVariance — tournament example', () {
    // ROI 30% → 0.3 buy-ins per tournament, SD 3 buy-ins, 100 tournaments.
    final r = computeVariance(
        meanPerUnit: 0.3, sdPerUnit: 3, units: 100, bankroll: 100);

    test('EV 30 buy-ins, σ 30 buy-ins', () {
      expect(r.ev, closeTo(30, 1e-9));
      expect(r.sd, closeTo(30, 1e-9));
    });

    test('RoR with 100 buy-ins', () {
      // exp(−2·0.3·100/9) ≈ 0.001273
      expect(r.riskOfRuin, closeTo(0.001273, 5e-6));
    });
  });

  group('computeVariance — edges', () {
    test('non-positive winrate: RoR 1.0, no finite min bankroll', () {
      final r = computeVariance(
          meanPerUnit: -2, sdPerUnit: 90, units: 100, bankroll: 5000);
      expect(r.riskOfRuin, 1.0);
      expect(r.bankrollForRoR5, isNull);
      expect(r.bankrollForRoR1, isNull);
    });

    test('no bankroll → null RoR', () {
      final r = computeVariance(meanPerUnit: 5, sdPerUnit: 90, units: 100);
      expect(r.riskOfRuin, isNull);
    });

    test('zero SD: pLoss is 0/1 by sign, RoR 0 for a winner', () {
      final w = computeVariance(
          meanPerUnit: 5, sdPerUnit: 0, units: 100, bankroll: 10);
      expect(w.pLoss, 0.0);
      expect(w.riskOfRuin, 0.0);
      final l = computeVariance(meanPerUnit: -5, sdPerUnit: 0, units: 100);
      expect(l.pLoss, 1.0);
    });
  });

  group('simulatePaths', () {
    test('deterministic per seed, differs across seeds', () {
      final a = simulatePaths(
          meanPerUnit: 5, sdPerUnit: 90, units: 100, seed: 42);
      final b = simulatePaths(
          meanPerUnit: 5, sdPerUnit: 90, units: 100, seed: 42);
      final c = simulatePaths(
          meanPerUnit: 5, sdPerUnit: 90, units: 100, seed: 43);
      expect(a[3][17], b[3][17]);
      expect(a[3][17] == c[3][17], isFalse);
    });

    test('shape: paths × (steps+1), all starting at 0', () {
      final p = simulatePaths(
          meanPerUnit: 5,
          sdPerUnit: 90,
          units: 100,
          paths: 7,
          steps: 50,
          seed: 1);
      expect(p, hasLength(7));
      expect(p.first, hasLength(51));
      expect(p.every((path) => path.first == 0), isTrue);
    });

    test('grand mean of finals lands near EV (fixed seed, loose band)', () {
      final p = simulatePaths(
          meanPerUnit: 5,
          sdPerUnit: 90,
          units: 100,
          paths: 200,
          steps: 60,
          seed: 7);
      final mean =
          p.map((x) => x.last).reduce((a, b) => a + b) / p.length;
      // EV 500, σ_total 900 → SE of the mean of 200 ≈ 64; ±3 SE band.
      expect(mean, closeTo(500, 200));
    });
  });

  group('simulateDownswings', () {
    test('deterministic per seed; p95 ≥ median ≥ 0', () {
      const params = DownswingParams(
          meanPerUnit: 5, sdPerUnit: 90, units: 100, trials: 500, seed: 11);
      final a = simulateDownswings(params);
      final b = simulateDownswings(params);
      expect(a.medianMaxDrawdown, b.medianMaxDrawdown);
      expect(a.p95MaxDrawdown, greaterThanOrEqualTo(a.medianMaxDrawdown));
      expect(a.medianMaxDrawdown, greaterThanOrEqualTo(0));
      expect(a.pDrawdownExceedsBankroll, isNull);
    });

    test('zero SD → zero drawdown for a winner', () {
      final s = simulateDownswings(const DownswingParams(
          meanPerUnit: 5,
          sdPerUnit: 0,
          units: 100,
          trials: 100,
          seed: 3));
      expect(s.medianMaxDrawdown, 0);
      expect(s.p95MaxDrawdown, 0);
    });

    test('bust probability populated with a bankroll, sane bounds', () {
      final s = simulateDownswings(const DownswingParams(
          meanPerUnit: 5,
          sdPerUnit: 90,
          units: 100,
          bankroll: 1500,
          trials: 1000,
          seed: 5));
      expect(s.pDrawdownExceedsBankroll, isNotNull);
      expect(s.pDrawdownExceedsBankroll!, inInclusiveRange(0, 1));
      // A tiny bankroll must bust more often than a huge one.
      final tiny = simulateDownswings(const DownswingParams(
          meanPerUnit: 5,
          sdPerUnit: 90,
          units: 100,
          bankroll: 100,
          trials: 1000,
          seed: 5));
      expect(tiny.pDrawdownExceedsBankroll!,
          greaterThan(s.pDrawdownExceedsBankroll!));
    });
  });
}
