import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/session_filter.dart';
import 'package:tablelab/models/session_model.dart';

SessionModel _session({
  String gameType = 'cash',
  String stakes = '1/2',
  String? location,
  String date = '2026-05-15',
  double profitLoss = 100,
}) {
  return SessionModel(
    id: 'test',
    date: date,
    stakes: stakes,
    gameType: gameType,
    buyIn: 200,
    cashOut: 200 + profitLoss,
    profitLoss: profitLoss,
    startTime: '18:00',
    endTime: '22:00',
    durationMinutes: 240,
    location: location,
    createdAt: '${date}T18:00:00Z',
    currency: 'CAD',
  );
}

void main() {
  // ── isEmpty ──────────────────────────────────────────────────────────────────

  group('SessionFilter.isEmpty', () {
    test('default filter is empty', () {
      expect(const SessionFilter().isEmpty, isTrue);
    });

    test('filter with any field set is not empty', () {
      expect(const SessionFilter(gameType: 'cash').isEmpty, isFalse);
      expect(const SessionFilter(stakes: {'1/2'}).isEmpty, isFalse);
      expect(const SessionFilter(locations: {'Casino'}).isEmpty, isFalse);
      expect(const SessionFilter(dateFrom: '2026-01-01').isEmpty, isFalse);
      expect(const SessionFilter(dateTo: '2026-12-31').isEmpty, isFalse);
      expect(const SessionFilter(result: SessionResult.win).isEmpty, isFalse);
    });

    test('empty stakes/locations sets count as no filter', () {
      expect(const SessionFilter(stakes: {}, locations: {}).isEmpty, isTrue);
    });
  });

  // ── gameType filter ──────────────────────────────────────────────────────────

  group('gameType filter', () {
    test('cash filter passes cash sessions', () {
      const f = SessionFilter(gameType: 'cash');
      expect(f.matches(_session(gameType: 'cash')), isTrue);
    });

    test('cash filter rejects tournaments', () {
      const f = SessionFilter(gameType: 'cash');
      expect(f.matches(_session(gameType: 'tournament')), isFalse);
      expect(f.matches(_session(gameType: 'sit_and_go')), isFalse);
    });

    test('tournament filter matches both tournament and sit_and_go', () {
      const f = SessionFilter(gameType: 'tournament');
      expect(f.matches(_session(gameType: 'tournament')), isTrue);
      expect(f.matches(_session(gameType: 'sit_and_go')), isTrue);
    });

    test('tournament filter rejects cash sessions', () {
      const f = SessionFilter(gameType: 'tournament');
      expect(f.matches(_session(gameType: 'cash')), isFalse);
    });
  });

  // ── stakes filter (multi-select) ─────────────────────────────────────────────

  group('stakes filter', () {
    test('single selected stake matches', () {
      const f = SessionFilter(stakes: {'2/5'});
      expect(f.matches(_session(stakes: '2/5')), isTrue);
      expect(f.matches(_session(stakes: '1/2')), isFalse);
    });

    test('matches a session in ANY of the selected stakes', () {
      const f = SessionFilter(stakes: {'1/2', '5/10'});
      expect(f.matches(_session(stakes: '1/2')), isTrue);
      expect(f.matches(_session(stakes: '5/10')), isTrue);
      expect(f.matches(_session(stakes: '2/5')), isFalse);
    });
  });

  // ── location filter (multi-select) ───────────────────────────────────────────

  group('location filter', () {
    test('matches a session in ANY of the selected locations', () {
      const f = SessionFilter(locations: {'Playground Poker', 'Casino Niagara'});
      expect(f.matches(_session(location: 'Playground Poker')), isTrue);
      expect(f.matches(_session(location: 'Casino Niagara')), isTrue);
      expect(f.matches(_session(location: 'Other Room')), isFalse);
    });

    test('null session location rejected when filter set', () {
      const f = SessionFilter(locations: {'Playground Poker'});
      expect(f.matches(_session(location: null)), isFalse);
    });
  });

  // ── date range filter ────────────────────────────────────────────────────────

  group('date range filter', () {
    test('session on dateFrom boundary is included', () {
      const f = SessionFilter(dateFrom: '2026-05-01');
      expect(f.matches(_session(date: '2026-05-01')), isTrue);
    });

    test('session on dateTo boundary is included', () {
      const f = SessionFilter(dateTo: '2026-05-31');
      expect(f.matches(_session(date: '2026-05-31')), isTrue);
    });

    test('session before dateFrom is excluded', () {
      const f = SessionFilter(dateFrom: '2026-05-01');
      expect(f.matches(_session(date: '2026-04-30')), isFalse);
    });

    test('session after dateTo is excluded', () {
      const f = SessionFilter(dateTo: '2026-05-31');
      expect(f.matches(_session(date: '2026-06-01')), isFalse);
    });

    test('session within range is included', () {
      const f = SessionFilter(dateFrom: '2026-05-01', dateTo: '2026-05-31');
      expect(f.matches(_session(date: '2026-05-15')), isTrue);
    });
  });

  // ── result filter ────────────────────────────────────────────────────────────

  group('result filter', () {
    test('win filter passes winning, rejects break-even and losing', () {
      const f = SessionFilter(result: SessionResult.win);
      expect(f.matches(_session(profitLoss: 100)), isTrue);
      expect(f.matches(_session(profitLoss: 0)), isFalse);
      expect(f.matches(_session(profitLoss: -50)), isFalse);
    });

    test('loss filter passes losing, rejects winning', () {
      const f = SessionFilter(result: SessionResult.loss);
      expect(f.matches(_session(profitLoss: -1)), isTrue);
      expect(f.matches(_session(profitLoss: 100)), isFalse);
    });
  });

  // ── combined filters ─────────────────────────────────────────────────────────

  group('combined filters (AND across criteria, OR within a multi-set)', () {
    test('cash + stakes + win — all three must match', () {
      const f = SessionFilter(
        gameType: 'cash',
        stakes: {'2/5'},
        result: SessionResult.win,
      );
      expect(
          f.matches(_session(gameType: 'cash', stakes: '2/5', profitLoss: 200)),
          isTrue);
      expect(
          f.matches(_session(
              gameType: 'tournament', stakes: '2/5', profitLoss: 200)),
          isFalse);
      expect(
          f.matches(_session(gameType: 'cash', stakes: '1/2', profitLoss: 200)),
          isFalse);
      expect(
          f.matches(
              _session(gameType: 'cash', stakes: '2/5', profitLoss: -100)),
          isFalse);
    });

    test('date range + multiple locations', () {
      const f = SessionFilter(
        dateFrom: '2026-05-01',
        dateTo: '2026-05-31',
        locations: {'Playground Poker', 'Casino Niagara'},
      );
      expect(
          f.matches(_session(date: '2026-05-15', location: 'Casino Niagara')),
          isTrue);
      expect(
          f.matches(_session(date: '2026-06-15', location: 'Playground Poker')),
          isFalse); // right location, wrong date
      expect(f.matches(_session(date: '2026-05-15', location: 'Other')),
          isFalse); // right date, wrong location
    });
  });

  // ── copyWith ─────────────────────────────────────────────────────────────────

  group('SessionFilter.copyWith', () {
    test('preserves unspecified fields, replaces the set passed', () {
      const f = SessionFilter(gameType: 'cash', stakes: {'1/2'});
      final updated = f.copyWith(stakes: {'2/5', '5/10'});
      expect(updated.gameType, equals('cash'));
      expect(updated.stakes, equals({'2/5', '5/10'}));
    });

    test('can clear a nullable field by passing null', () {
      const f = SessionFilter(gameType: 'cash', stakes: {'1/2'});
      final cleared = f.copyWith(gameType: null);
      expect(cleared.gameType, isNull);
      expect(cleared.stakes, equals({'1/2'}));
    });

    test('clearing a multi-set means passing an empty set', () {
      const f = SessionFilter(stakes: {'1/2'});
      expect(f.copyWith(stakes: {}).isEmpty, isTrue);
    });
  });

  // ── empty filter matches everything ─────────────────────────────────────────

  group('empty filter', () {
    test('matches any session', () {
      expect(const SessionFilter().matches(_session(gameType: 'cash')), isTrue);
      expect(const SessionFilter().matches(_session(gameType: 'tournament')),
          isTrue);
      expect(const SessionFilter().matches(_session(profitLoss: -500)), isTrue);
    });
  });
}
