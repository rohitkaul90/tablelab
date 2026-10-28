import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/screens/metric_chart_screen.dart';

import '../helpers/pump_app.dart';

/// crash-issues-15: `_labelEvery` did `.clamp(2, count)`, and `num.clamp`
/// throws `Invalid argument(s)` when lower > upper — so a chart with a SINGLE
/// period bucket (one logged session, or a lookback that leaves one bar)
/// crashed inside LayoutBuilder on every open of that metric.
void main() {
  SessionModel session(String date, {double profit = 50, String type = 'cash'}) =>
      SessionModel(
        id: 's-$date',
        date: date,
        stakes: '1/2',
        gameType: type,
        buyIn: 200,
        cashOut: 200 + profit,
        profitLoss: profit,
        startTime: '18:00',
        endTime: '22:00',
        durationMinutes: 240,
        createdAt: '${date}T18:00:00Z',
        currency: 'USD',
      );

  group('chartLabelEvery', () {
    test('a single (or empty) bucket never throws and shows its label', () {
      expect(chartLabelEvery(360, 1), 1);
      expect(chartLabelEvery(360, 0), 1);
      expect(chartLabelEvery(0, 1), 1);
      expect(chartLabelEvery(double.infinity, 10), 1);
      expect(chartLabelEvery(double.nan, 10), 1);
    });

    test('shows every label while they fit, then thins to ~48 px apart', () {
      expect(chartLabelEvery(360, 2), 1);
      expect(chartLabelEvery(360, 7), 1); // 7 fit in 360/48 = 7 slots
      expect(chartLabelEvery(360, 14), 2);
      expect(chartLabelEvery(360, 52), 8);
    });

    test('an unlaid-out (zero) width degrades to the sparsest thinning', () {
      expect(chartLabelEvery(0, 10), 5); // maxLabels floors at 2
      expect(chartLabelEvery(0, 2), 1);
    });
  });

  group('MetricChartScreen with one period bucket', () {
    for (final metric in [
      StatMetric.profit,
      StatMetric.sessions,
      StatMetric.hours,
      StatMetric.winLoss, // the separate _WinLossChart path
    ]) {
      testWidgets('$metric renders a single-bar chart without throwing',
          (tester) async {
        await pumpApp(
          tester,
          MetricChartScreen(
            metric: metric,
            sessions: [session('2026-10-20')],
            displayCurrency: 'USD',
            activeFilters: const [],
          ),
          size: const Size(360, 800),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$metric');
        // Pin the code path: the single bar is CHARTED, not routed to an empty
        // state (which would silently stop exercising chartLabelEvery).
        expect(find.byType(BarChart), findsOneWidget, reason: '$metric');
      });
    }

    testWidgets('two sessions in the same month still make one (monthly) bucket',
        (tester) async {
      await pumpApp(
        tester,
        MetricChartScreen(
          metric: StatMetric.profit,
          sessions: [session('2026-10-20'), session('2026-10-21', profit: -30)],
          displayCurrency: 'USD',
          activeFilters: const [],
        ),
        size: const Size(360, 800),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BarChart), findsOneWidget);
    });
  });
}
