import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/models/stats_filter.dart';
import 'package:tablelab/screens/analytics_screen.dart';

import '../helpers/pump_app.dart';

/// The Stats factor + Tips tabs render in Dutch on a 360-wide phone without
/// overflow, with stable keys grouping sessions regardless of language.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('nl');
  });

  SessionModel cash(String date, double pl, String start, int minutes) =>
      SessionModel(
        id: date + start,
        date: date,
        stakes: '1/2',
        gameType: 'cash',
        buyIn: 200,
        cashOut: 200 + pl,
        profitLoss: pl,
        startTime: start,
        endTime: '23:00',
        durationMinutes: minutes,
        createdAt: '${date}T12:00:00Z',
        currency: 'EUR',
      );

  // Long evening sessions win, short morning ones lose — enough separation
  // for the Welch test to emit at least one recommendation.
  final sessions = [
    for (var i = 0; i < 6; i++) ...[
      cash('2026-0${i + 1}-05', 400 + i * 10.0, '19:00', 240),
      cash('2026-0${i + 1}-10', -300 - i * 10.0, '09:00', 120),
    ],
  ];

  final nl = lookupAppLocalizations(const Locale('nl'));
  final data =
      AnalyticsData.compute(sessions, const StatsFilter(), 'EUR', nl);

  testWidgets('factor tabs render in Dutch at 360dp without overflow',
      (tester) async {
    final factors = analyticsFactors(data, nl);
    expect(factors.map((f) => f.id), contains('day'));
    for (final f in factors) {
      await pumpApp(
        tester,
        Scaffold(
          body: AnalyticsFactorTab(
            data: data,
            factor: f,
            sort: InsightSort.rate,
            onSortChanged: (_) {},
          ),
        ),
        locale: const Locale('nl'),
        size: const Size(360, 800),
      );
      expect(tester.takeException(), isNull, reason: f.id);
      // A card needs ≥2 groups to render; the fixture's time-of-day split
      // (evening vs morning) always has two, so its Dutch title must show.
      if (f.id == 'time') {
        expect(find.text(f.title), findsOneWidget);
        expect(find.text(nl.bucketTimeEvening), findsOneWidget);
      }
    }
  });

  testWidgets('tips tab renders Dutch recommendation sentences', (tester) async {
    await pumpApp(
      tester,
      Scaffold(body: AnalyticsTipsTab(data: data)),
      locale: const Locale('nl'),
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(nl.statsRecsBasedOn), findsOneWidget);
    expect(find.textContaining('Schedule more sessions'), findsNothing);
  });
}
