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
  });
}
