import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/utils/session_export.dart';

SessionModel _session({
  String? country,
  int? tableSize,
  int? handsPerHour,
  int? breakMinutes,
  List<BuyinEvent> buyinEvents = const [],
  List<ExpenseEvent> expenseEvents = const [],
}) =>
    SessionModel(
      id: 'id-1',
      date: '2026-07-01',
      stakes: '1/2',
      gameType: 'cash',
      buyIn: 300,
      cashOut: 450,
      profitLoss: 150,
      startTime: '18:00',
      endTime: '23:00',
      durationMinutes: 300,
      createdAt: '2026-07-01T18:00:00Z',
      currency: 'CAD',
      country: country,
      tableSize: tableSize,
      handsPerHour: handsPerHour,
      breakMinutes: breakMinutes,
      buyinEvents: buyinEvents,
      expenseEvents: expenseEvents,
    );

void main() {
  group('sessionExportRow', () {
    test('row length always matches header length', () {
      expect(sessionExportRow(_session()).length,
          kSessionExportHeaders.length);
      expect(
        sessionExportRow(_session(
          country: 'Canada',
          tableSize: 9,
          handsPerHour: 25,
          breakMinutes: 20,
          buyinEvents: [
            BuyinEvent(amount: 300, ts: DateTime.utc(2026, 7), kind: 'buyin'),
          ],
          expenseEvents: [
            ExpenseEvent(
                amount: 15, category: 'tip', ts: DateTime.utc(2026, 7)),
          ],
        )).length,
        kSessionExportHeaders.length,
      );
    });

    test('exports currency and schema fields added after the original list',
        () {
      final row = sessionExportRow(
          _session(country: 'Canada', tableSize: 9, handsPerHour: 25));
      int col(String h) => kSessionExportHeaders.indexOf(h);
      expect(row[col('currency')], 'CAD');
      expect(row[col('country')], 'Canada');
      expect(row[col('table_size')], 9);
      expect(row[col('hands_per_hour')], 25);
    });

    test('expenses export as totals; net stays derived', () {
      final row = sessionExportRow(_session(expenseEvents: [
        ExpenseEvent(amount: 15, category: 'tip', ts: DateTime.utc(2026, 7)),
        ExpenseEvent(amount: 35, category: 'food', ts: DateTime.utc(2026, 7)),
      ]));
      int col(String h) => kSessionExportHeaders.indexOf(h);
      expect(row[col('total_expenses')], 50);
      expect(row[col('net_after_expenses')], 100); // 150 profit − 50 expenses
      expect(row[col('profit_loss')], 150); // poker result stays pure
    });

    test('nullable / untracked fields export blank, not zero', () {
      final row = sessionExportRow(_session());
      int col(String h) => kSessionExportHeaders.indexOf(h);
      expect(row[col('country')], '');
      expect(row[col('table_size')], '');
      expect(row[col('hands_per_hour')], '');
      expect(row[col('break_minutes')], '');
      // No buy-in event history (pre-live-recorder) → unknown, not 0.
      expect(row[col('buyin_count')], '');
      // But expenses genuinely are 0 when none were logged.
      expect(row[col('total_expenses')], 0);
      expect(row[col('net_after_expenses')], 150);
    });

    test('buyin_count reflects the recorded event history', () {
      final row = sessionExportRow(_session(buyinEvents: [
        BuyinEvent(amount: 300, ts: DateTime.utc(2026, 7), kind: 'buyin'),
        BuyinEvent(amount: 200, ts: DateTime.utc(2026, 7), kind: 'rebuy'),
        BuyinEvent(amount: 100, ts: DateTime.utc(2026, 7), kind: 'addon'),
      ]));
      expect(row[kSessionExportHeaders.indexOf('buyin_count')], 3);
    });

    test('headers contain no duplicates', () {
      expect(kSessionExportHeaders.toSet().length,
          kSessionExportHeaders.length);
    });
  });
}
