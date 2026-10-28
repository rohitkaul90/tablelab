import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/models/stats_filter.dart';
import 'package:tablelab/screens/analytics_screen.dart';

import '../helpers/pump_app.dart';

/// Device QA 2026-10-28: a new account with two sessions (CAD + JPY, two
/// dates on the SAME weekday) saw the Day / Time / Table tabs render blank —
/// the insight card hid itself when a breakdown had fewer than two groups,
/// with no explanation. The factor tabs must say why instead.
void main() {
  SessionModel cash(String date, String currency, String start) => SessionModel(
        id: '$date-$currency',
        date: date,
        stakes: '1/2',
        gameType: 'cash',
        buyIn: 200,
        cashOut: 250,
        profitLoss: 50,
        startTime: start,
        endTime: '23:00',
        durationMinutes: 240,
        createdAt: '${date}T12:00:00Z',
        currency: currency,
      );

  final en = lookupAppLocalizations(const Locale('en'));

  AnalyticsFactor factorById(AnalyticsData d, String id) =>
      analyticsFactors(d, en).firstWhere((f) => f.id == id);

  Future<void> pumpFactor(WidgetTester tester, AnalyticsData d, String id) =>
      pumpApp(
        tester,
        Scaffold(
          body: AnalyticsFactorTab(
            data: d,
            factor: factorById(d, id),
            sort: InsightSort.rate,
            onSortChanged: (_) {},
          ),
        ),
        size: const Size(360, 800),
      );

  testWidgets('one weekday / one time band → the tab explains, not blank',
      (tester) async {
    // Oct 20 and Oct 27 2026 are both Tuesdays; both sessions start at 19:00.
    final d = AnalyticsData.compute(
      [cash('2026-10-20', 'CAD', '19:00'), cash('2026-10-27', 'JPY', '19:00')],
      const StatsFilter(),
      'CAD',
      en,
    );
    final ids = analyticsFactors(d, en).map((f) => f.id).toList();
    expect(ids, containsAll(['day', 'time']));

    for (final id in ['day', 'time']) {
      await pumpFactor(tester, d, id);
      expect(tester.takeException(), isNull, reason: id);
      expect(find.text(en.statsFactorNeedTwoGroups), findsOneWidget,
          reason: '$id tab must explain the single group');
    }
  });

  testWidgets('two weekdays → the Day breakdown renders rows, no empty text',
      (tester) async {
    // Monday and Tuesday.
    final d = AnalyticsData.compute(
      [cash('2026-10-19', 'CAD', '19:00'), cash('2026-10-27', 'JPY', '19:00')],
      const StatsFilter(),
      'CAD',
      en,
    );
    await pumpFactor(tester, d, 'day');
    expect(tester.takeException(), isNull);
    expect(find.text(en.statsFactorNeedTwoGroups), findsNothing);
    expect(find.text(en.statsFactorDayTitle), findsOneWidget);
  });
}
