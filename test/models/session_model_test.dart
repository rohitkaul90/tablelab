import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/session_model.dart';

void main() {
  // ── fromMap ──────────────────────────────────────────────────────────────────

  group('SessionModel.fromMap', () {
    final Map<String, dynamic> fullMap = {
      'id': 'abc-123',
      'date': '2026-05-01',
      'stakes': '1/2',
      'game_type': 'cash',
      'buy_in': 200.0,
      'cash_out': 350.0,
      'profit_loss': 150.0,
      'start_time': '18:00',
      'end_time': '22:00',
      'duration_minutes': 240,
      'location': 'Playground Poker',
      'notes': 'Great session',
      'created_at': '2026-05-01T18:00:00Z',
      'rake_paid': 25.0,
      'finish_position': null,
      'total_entrants': null,
      'prize_won': null,
      'table_quality': 4,
      'currency': 'CAD',
      'hands_per_hour': 28,
      'country': 'Canada',
      'table_size': 8,
    };

    test('parses all required fields', () {
      final session = SessionModel.fromMap(fullMap);
      expect(session.id, equals('abc-123'));
      expect(session.date, equals('2026-05-01'));
      expect(session.stakes, equals('1/2'));
      expect(session.gameType, equals('cash'));
      expect(session.buyIn, equals(200.0));
      expect(session.cashOut, equals(350.0));
      expect(session.profitLoss, equals(150.0));
      expect(session.startTime, equals('18:00'));
      expect(session.endTime, equals('22:00'));
      expect(session.durationMinutes, equals(240));
      expect(session.currency, equals('CAD'));
      expect(session.createdAt, equals('2026-05-01T18:00:00Z'));
    });

    test('parses optional string fields', () {
      final session = SessionModel.fromMap(fullMap);
      expect(session.location, equals('Playground Poker'));
      expect(session.notes, equals('Great session'));
      expect(session.country, equals('Canada'));
    });

    test('parses optional numeric fields', () {
      final session = SessionModel.fromMap(fullMap);
      expect(session.rakePaid, equals(25.0));
      expect(session.tableQuality, equals(4));
      expect(session.handsPerHour, equals(28));
      expect(session.tableSize, equals(8));
    });

    test('handles null optional fields gracefully', () {
      final session = SessionModel.fromMap(fullMap);
      expect(session.finishPosition, isNull);
      expect(session.totalEntrants, isNull);
      expect(session.prizeWon, isNull);
    });

    test('coerces int buy_in to double', () {
      final map = {...fullMap, 'buy_in': 200, 'cash_out': 350, 'profit_loss': 150};
      final session = SessionModel.fromMap(map);
      expect(session.buyIn, equals(200.0));
      expect(session.buyIn, isA<double>());
    });

    test('defaults currency to CAD when absent', () {
      final map = Map<String, dynamic>.from(fullMap)..remove('currency');
      final session = SessionModel.fromMap(map);
      expect(session.currency, equals('CAD'));
    });

    test('parses tournament session fields', () {
      final tournamentMap = {
        ...fullMap,
        'game_type': 'tournament',
        'buy_in': 100.0,
        'cash_out': 500.0,
        'profit_loss': 400.0,
        'finish_position': 3,
        'total_entrants': 120,
        'prize_won': 500.0,
      };
      final session = SessionModel.fromMap(tournamentMap);
      expect(session.gameType, equals('tournament'));
      expect(session.finishPosition, equals(3));
      expect(session.totalEntrants, equals(120));
      expect(session.prizeWon, equals(500.0));
    });

    test('handles minimal required-only map', () {
      final minimalMap = {
        'id': 'min-id',
        'date': '2026-01-01',
        'stakes': 'N/A',
        'game_type': 'cash',
        'buy_in': 100,
        'cash_out': 100,
        'profit_loss': 0,
        'start_time': '12:00',
        'end_time': '14:00',
        'duration_minutes': 120,
        'created_at': '2026-01-01T12:00:00Z',
      };
      final session = SessionModel.fromMap(minimalMap);
      expect(session.id, equals('min-id'));
      expect(session.location, isNull);
      expect(session.notes, isNull);
      expect(session.currency, equals('CAD'));
      expect(session.tableSize, isNull);
    });

    test('legacy session (no live columns) defaults to completed', () {
      final session = SessionModel.fromMap(fullMap);
      expect(session.status, equals('completed'));
      expect(session.isLive, isFalse);
      expect(session.startedAt, isNull);
      expect(session.buyinEvents, isEmpty);
      expect(session.currentStack, isNull);
      // totalBuyIn falls back to the buy_in column when no events recorded.
      expect(session.totalBuyIn, equals(200.0));
    });
  });

  // ── live session recorder ───────────────────────────────────────────────────

  group('SessionModel live fields', () {
    final liveMap = {
      'id': 'live-1',
      'date': '2026-06-16',
      'stakes': '2/5',
      'game_type': 'cash',
      'buy_in': 800.0, // running sum of the events below
      'cash_out': 0,
      'profit_loss': 0,
      'start_time': '19:00',
      'end_time': '19:00',
      'duration_minutes': 0,
      'created_at': '2026-06-16T19:00:00Z',
      'currency': 'USD',
      'status': 'live',
      'started_at': '2026-06-16T19:00:00Z',
      'current_stack': 1100.0,
      'buyin_events': [
        {'amount': 500.0, 'ts': '2026-06-16T19:00:00Z', 'kind': 'buyin'},
        {'amount': 300.0, 'ts': '2026-06-16T20:30:00Z', 'kind': 'rebuy'},
      ],
    };

    test('parses status, startedAt, currentStack and events', () {
      final s = SessionModel.fromMap(liveMap);
      expect(s.isLive, isTrue);
      expect(s.startedAt, equals(DateTime.parse('2026-06-16T19:00:00Z')));
      expect(s.currentStack, equals(1100.0));
      expect(s.buyinEvents.length, equals(2));
      expect(s.buyinEvents[1].kind, equals('rebuy'));
      expect(s.buyinEvents[1].amount, equals(300.0));
    });

    test('totalBuyIn sums the events (not the buy_in column)', () {
      final s = SessionModel.fromMap(liveMap);
      expect(s.totalBuyIn, equals(800.0));
      // Live net = currentStack - totalBuyIn.
      expect(s.currentStack! - s.totalBuyIn, equals(300.0));
    });

    test('BuyinEvent round-trips through json', () {
      final e = BuyinEvent.fromJson(
          {'amount': 250.0, 'ts': '2026-06-16T21:00:00Z', 'kind': 'addon'});
      final j = e.toJson();
      final back = BuyinEvent.fromJson(j);
      expect(back.amount, equals(250.0));
      expect(back.kind, equals('addon'));
      expect(back.ts, equals(DateTime.parse('2026-06-16T21:00:00Z')));
    });

    test('malformed buyin_events falls back to empty', () {
      final s = SessionModel.fromMap({...liveMap, 'buyin_events': 'oops'});
      expect(s.buyinEvents, isEmpty);
      // With no parseable events, totalBuyIn falls back to the column.
      expect(s.totalBuyIn, equals(800.0));
    });

    test('parses break fields and isOnBreak', () {
      final s = SessionModel.fromMap({
        ...liveMap,
        'break_minutes': 15,
        'break_started_at': '2026-06-16T21:00:00Z',
      });
      expect(s.breakMinutes, equals(15));
      expect(s.isOnBreak, isTrue);
      expect(s.breakStartedAt, equals(DateTime.parse('2026-06-16T21:00:00Z')));
    });
  });

  // ── expenses ────────────────────────────────────────────────────────────────

  group('SessionModel expenses', () {
    final baseMap = {
      'id': 'e-1',
      'date': '2026-06-16',
      'stakes': '2/5',
      'game_type': 'cash',
      'buy_in': 500.0,
      'cash_out': 900.0,
      'profit_loss': 400.0, // pure poker result
      'start_time': '19:00',
      'end_time': '23:00',
      'duration_minutes': 240,
      'created_at': '2026-06-16T19:00:00Z',
      'currency': 'USD',
      'expense_events': [
        {'amount': 40.0, 'category': 'tip', 'ts': '2026-06-16T23:00:00Z'},
        {
          'amount': 25.0,
          'category': 'food',
          'note': 'dinner',
          'ts': '2026-06-16T21:00:00Z'
        },
      ],
    };

    test('parses expense events and totals', () {
      final s = SessionModel.fromMap(baseMap);
      expect(s.expenseEvents.length, equals(2));
      expect(s.expenseEvents[1].note, equals('dinner'));
      expect(s.totalExpenses, equals(65.0));
    });

    test('profitLoss stays pure; net is derived', () {
      final s = SessionModel.fromMap(baseMap);
      expect(s.profitLoss, equals(400.0));
      expect(s.netAfterExpenses, equals(335.0));
    });

    test('no expenses → net equals profitLoss', () {
      final s = SessionModel.fromMap(
          Map<String, dynamic>.from(baseMap)..remove('expense_events'));
      expect(s.totalExpenses, equals(0.0));
      expect(s.netAfterExpenses, equals(400.0));
    });

    test('ExpenseEvent round-trips and omits empty note', () {
      final e = ExpenseEvent(
          amount: 30, category: 'massage', ts: DateTime.parse('2026-06-16T22:00:00Z'));
      final j = e.toJson();
      expect(j.containsKey('note'), isFalse);
      final back = ExpenseEvent.fromJson(j);
      expect(back.category, equals('massage'));
      expect(back.amount, equals(30.0));
    });

    test('expenseCategoryLabel maps known + unknown', () {
      expect(expenseCategoryLabel('travel'), equals('Travel / trip'));
      expect(expenseCategoryLabel('nonsense'), equals('Other'));
    });

    test('a malformed event entry is skipped, not fatal to the fetch', () {
      final s = SessionModel.fromMap({
        ...baseMap,
        'expense_events': [
          {'amount': 40.0, 'category': 'tip', 'ts': '2026-06-16T23:00:00Z'},
          {'category': 'food'}, // missing amount + ts → skipped, not thrown
          'garbage', // non-map → skipped
        ],
        'buyin_events': [
          {'amount': 500.0, 'ts': '2026-06-16T19:00:00Z', 'kind': 'buyin'},
          {'kind': 'rebuy'}, // missing amount + ts → skipped
        ],
      });
      expect(s.expenseEvents.length, equals(1));
      expect(s.totalExpenses, equals(40.0));
      expect(s.buyinEvents.length, equals(1));
      expect(s.totalBuyIn, equals(500.0));
    });
  });
}
