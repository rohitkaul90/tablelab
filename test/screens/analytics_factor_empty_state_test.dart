import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/models/stats_filter.dart';
import 'package:tablelab/screens/analytics_screen.dart';

import '../helpers/pump_app.dart';

/// Owner decision 2026-10-28: every Stats breakdown tab is ALWAYS visible so
/// users see what Stats can tell them; a tab without two groups to compare
/// explains what to log (and whether the filter is hiding sessions) instead
/// of rendering blank (the device-QA bug) or disappearing.
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
  const allIds = [
    'stakes', 'buyIns', 'fieldSize', 'gameType', 'day', 'time', 'length',
    'table', 'location', 'venue',
  ];

  AnalyticsData compute(List<SessionModel> s, [StatsFilter f = const StatsFilter()]) =>
      AnalyticsData.compute(s, f, 'CAD', en);

  Future<void> pumpFactor(WidgetTester tester, AnalyticsData d, String id) =>
      pumpApp(
        tester,
        Scaffold(
          body: AnalyticsFactorTab(
            data: d,
            factor: analyticsFactors(d, en).firstWhere((f) => f.id == id),
            sort: InsightSort.rate,
            onSortChanged: (_) {},
          ),
        ),
        size: const Size(360, 800),
      );

  test('every breakdown is listed with no sessions, two sessions, or many', () {
    expect(analyticsFactors(compute([]), en).map((f) => f.id), allIds);
    // Device QA: two sessions, both Tuesdays, both 19:00, one rated.
    final two = compute([
      cash('2026-10-20', 'CAD', '19:00', tableQuality: 3),
      cash('2026-10-27', 'JPY', '19:00'),
    ]);
    expect(analyticsFactors(two, en).map((f) => f.id), allIds);
    for (final f in analyticsFactors(two, en)) {
      expect(f.emptyMessage, isNotEmpty, reason: f.id);
    }
  });

  testWidgets('a one-group tab says what to log, with no legend or sort menu',
      (tester) async {
    final d = compute([
      cash('2026-10-20', 'CAD', '19:00', tableQuality: 3),
      cash('2026-10-27', 'JPY', '19:00'),
    ]);
    final expected = {
      'day': en.statsFactorEmptyDay,
      'time': en.statsFactorEmptyTime,
      'table': en.statsFactorEmptyTable,
      'stakes': en.statsFactorEmptyStakes,
      'venue': en.statsFactorEmptyVenue,
      'buyIns': en.statsFactorEmptyBuyIns,
    };
    for (final e in expected.entries) {
      await pumpFactor(tester, d, e.key);
      expect(tester.takeException(), isNull, reason: e.key);
      expect(find.text(e.value), findsOneWidget, reason: e.key);
      expect(find.byIcon(Icons.sort), findsNothing, reason: '${e.key} sort');
      expect(find.text(en.statsFactorFilteredHint), findsNothing,
          reason: '${e.key}: no filter active');
    }
  });

  testWidgets('the filter hint appears only when the Stats filter hides sessions',
      (tester) async {
    // Monday + Tuesday evenings: Day has two groups unfiltered …
    final sessions = [cash('2026-10-19', 'CAD', '19:00'), cash('2026-10-27', 'JPY', '19:00')];
    // … but a tournament-only game-type filter leaves nothing in view.
    final d = compute(sessions, const StatsFilter(gameTypes: {'tournament'}));
    await pumpFactor(tester, d, 'day');
    expect(find.text(en.statsFactorEmptyDay), findsOneWidget);
    expect(find.text(en.statsFactorFilteredHint), findsOneWidget);
  });

  testWidgets('two weekdays → the Day tab renders rows and no empty text',
      (tester) async {
    final d = compute([cash('2026-10-19', 'CAD', '19:00'), cash('2026-10-27', 'JPY', '19:00')]);
    await pumpFactor(tester, d, 'day');
    expect(tester.takeException(), isNull);
    expect(find.text(en.statsFactorEmptyDay), findsNothing);
    expect(find.text(en.statsFactorDayTitle), findsOneWidget);
    expect(find.byIcon(Icons.sort), findsOneWidget);
  });
}
