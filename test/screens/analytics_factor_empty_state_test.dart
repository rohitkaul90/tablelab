import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/models/stats_filter.dart';
import 'package:tablelab/screens/analytics_screen.dart';

import '../helpers/pump_app.dart';

/// Device QA 2026-10-28: a new account with two sessions (CAD + JPY, two
/// dates on the SAME weekday, both evening, one table rating) saw the Day /
/// Time / Table tabs render blank — the tab appeared on "has data" while the
/// card inside hid itself on "fewer than two groups". A factor now exists only
/// when it has at least two distinct groups to compare (the rule Location and
/// Venue already followed).
void main() {
  SessionModel cash(String date, String currency, String start,
          {int? tableQuality}) =>
      SessionModel(
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
        tableQuality: tableQuality,
      );

  final en = lookupAppLocalizations(const Locale('en'));

  test('single-group breakdowns do not become tabs', () {
    // Oct 20 and Oct 27 2026 are both Tuesdays; both start 19:00; one rated.
    final d = AnalyticsData.compute(
      [
        cash('2026-10-20', 'CAD', '19:00', tableQuality: 3),
        cash('2026-10-27', 'JPY', '19:00'),
      ],
      const StatsFilter(),
      'CAD',
      en,
    );
    final ids = analyticsFactors(d, en).map((f) => f.id).toList();
    for (final id in ['day', 'time', 'table', 'stakes', 'length']) {
      expect(ids, isNot(contains(id)), reason: '$id has one group');
    }
  });

  test('distinctGroupCount counts non-empty keys only', () {
    final d = AnalyticsData.compute(
      [cash('2026-10-19', 'CAD', '19:00'), cash('2026-10-27', 'JPY', '09:00')],
      const StatsFilter(),
      'CAD',
      en,
    );
    final byId = {for (final f in analyticsFactors(d, en)) f.id: f};
    expect(distinctGroupCount(byId['day']!), 2); // Monday + Tuesday
    expect(distinctGroupCount(byId['time']!), 2); // morning + evening
    expect(byId.containsKey('table'), isFalse, reason: 'nothing rated');
  });

  testWidgets('two weekdays → the Day tab exists and renders rows',
      (tester) async {
    final d = AnalyticsData.compute(
      [cash('2026-10-19', 'CAD', '19:00'), cash('2026-10-27', 'JPY', '19:00')],
      const StatsFilter(),
      'CAD',
      en,
    );
    final day = analyticsFactors(d, en).firstWhere((f) => f.id == 'day');
    await pumpApp(
      tester,
      Scaffold(
        body: AnalyticsFactorTab(
          data: d,
          factor: day,
          sort: InsightSort.rate,
          onSortChanged: (_) {},
        ),
      ),
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(en.statsFactorNeedTwoGroups), findsNothing);
    expect(find.text(en.statsFactorDayTitle), findsOneWidget);
  });

  testWidgets('safety net: a tab handed a one-group factor explains itself',
      (tester) async {
    // Reachable only if a caller bypasses analyticsFactors' gate.
    final d = AnalyticsData.compute(
      [cash('2026-10-20', 'CAD', '19:00'), cash('2026-10-27', 'JPY', '19:00')],
      const StatsFilter(),
      'CAD',
      en,
    );
    final oneGroup = AnalyticsFactor(
      id: 'day',
      tabLabel: en.statsFactorDay,
      title: en.statsFactorDayTitle,
      sessions: d.filtered,
      keyFn: (s) => weekdayKey(s) ?? '',
    );
    await pumpApp(
      tester,
      Scaffold(
        body: AnalyticsFactorTab(
          data: d,
          factor: oneGroup,
          sort: InsightSort.rate,
          onSortChanged: (_) {},
        ),
      ),
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(en.statsFactorNeedTwoGroups), findsOneWidget);
  });
}
