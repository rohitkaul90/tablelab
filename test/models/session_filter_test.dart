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
      expect(const SessionFilter(stakes: '1/2').isEmpty, isFalse);
      expect(const SessionFilter(location: 'Casino').isEmpty, isFalse);
      expect(const SessionFilter(dateFrom: '2026-01-01').isEmpty, isFalse);
      expect(const SessionFilter(dateTo: '2026-12-31').isEmpty, isFalse);
      expect(const SessionFilter(result: SessionResult.win).isEmpty, isFalse);
    });
  });

  // ── gameType filter ──────────────────────────────────────────────────────────

  group('gameType filter', () {
    test('cash filter passes cash sessions', () {
      final f = const SessionFilter(gameType: 'cash');
      expect(f.matches(_session(gameType: 'cash')), isTrue);
    });

    test('cash filter rejects tournaments', () {
      final f = const SessionFilter(gameType: 'cash');
      expect(f.matches(_session(gameType: 'tournament')), isFalse);
      expect(f.matches(_session(gameType: 'sit_and_go')), isFalse);
    });

    test('tournament filter matches both tournament and sit_and_go', () {
      final f = const SessionFilter(gameType: 'tournament');
      expect(f.matches(_session(gameType: 'tournament')), isTrue);
      expect(f.matches(_session(gameType: 'sit_and_go')), isTrue);
    });

    test('tournament filter rejects cash sessions', () {
      final f = const SessionFilter(gameType: 'tournament');
      expect(f.matches(_session(gameType: 'cash')), isFalse);
    });
  });

  // ── stakes filter ────────────────────────────────────────────────────────────

  group('stakes filter', () {
    test('exact match passes', () {
      final f = const SessionFilter(stakes: '2/5');
      expect(f.matches(_session(stakes: '2/5')), isTrue);
    });

    test('different stakes rejected', () {
      final f = const SessionFilter(stakes: '2/5');
      expect(f.matches(_session(stakes: '1/2')), isFalse);
      expect(f.matches(_session(stakes: '5/10')), isFalse);
    });
  });

  // ── location filter ──────────────────────────────────────────────────────────

  group('location filter', () {
    test('exact location match passes', () {
      final f = const SessionFilter(location: 'Playground Poker');
      expect(f.matches(_session(location: 'Playground Poker')), isTrue);
    });

    test('different location rejected', () {
      final f = const SessionFilter(location: 'Playground Poker');
      expect(f.matches(_session(location: 'Casino Niagara')), isFalse);
    });

    test('null session location rejected when filter set', () {
      final f = const SessionFilter(location: 'Playground Poker');
      expect(f.matches(_session(location: null)), isFalse);
    });
  });

  // ── date range filter ────────────────────────────────────────────────────────

  group('date range filter', () {
    test('session on dateFrom boundary is included', () {
      final f = const SessionFilter(dateFrom: '2026-05-01');
      expect(f.matches(_session(date: '2026-05-01')), isTrue);
    });

    test('session on dateTo boundary is included', () {
      final f = const SessionFilter(dateTo: '2026-05-31');
      expect(f.matches(_session(date: '2026-05-31')), isTrue);
    });

    test('session before dateFrom is excluded', () {
      final f = const SessionFilter(dateFrom: '2026-05-01');
      expect(f.matches(_session(date: '2026-04-30')), isFalse);
    });

    test('session after dateTo is excluded', () {
      final f = const SessionFilter(dateTo: '2026-05-31');
      expect(f.matches(_session(date: '2026-06-01')), isFalse);
    });

    test('session within range is included', () {
      final f = const SessionFilter(
          dateFrom: '2026-05-01', dateTo: '2026-05-31');
      expect(f.matches(_session(date: '2026-05-15')), isTrue);
    });

    test('session outside range is excluded', () {
      final f = const SessionFilter(
          dateFrom: '2026-05-01', dateTo: '2026-05-31');
      expect(f.matches(_session(date: '2026-04-01')), isFalse);
      expect(f.matches(_session(date: '2026-06-15')), isFalse);
    });
  });

  // ── result filter ────────────────────────────────────────────────────────────

  group('result filter', () {
    test('win filter passes winning sessions', () {
      final f = const SessionFilter(result: SessionResult.win);
      expect(f.matches(_session(profitLoss: 100)), isTrue);
      expect(f.matches(_session(profitLoss: 0.01)), isTrue);
    });

    test('win filter rejects break-even and losing sessions', () {
      final f = const SessionFilter(result: SessionResult.win);
      expect(f.matches(_session(profitLoss: 0)), isFalse);
      expect(f.matches(_session(profitLoss: -50)), isFalse);
    });

    test('loss filter passes losing sessions', () {
      final f = const SessionFilter(result: SessionResult.loss);
      expect(f.matches(_session(profitLoss: -1)), isTrue);
      expect(f.matches(_session(profitLoss: -500)), isTrue);
    });

    test('loss filter rejects winning sessions', () {
      final f = const SessionFilter(result: SessionResult.loss);
      expect(f.matches(_session(profitLoss: 100)), isFalse);
    });

    test('loss filter includes break-even sessions', () {
      final f = const SessionFilter(result: SessionResult.loss);
      // Filter rejects only profitLoss > 0; break-even (0) is not a win so it passes.
      expect(f.matches(_session(profitLoss: 0)), isTrue);
    });
  });

  // ── combined filters ─────────────────────────────────────────────────────────

  group('combined filters (AND logic)', () {
    test('cash + stakes + win — all three must match', () {
      final f = const SessionFilter(
        gameType: 'cash',
        stakes: '2/5',
        result: SessionResult.win,
      );
      // All match
      expect(
          f.matches(_session(gameType: 'cash', stakes: '2/5', profitLoss: 200)),
          isTrue);
      // Wrong game type
      expect(
          f.matches(
              _session(gameType: 'tournament', stakes: '2/5', profitLoss: 200)),
          isFalse);
      // Wrong stakes
      expect(
          f.matches(_session(gameType: 'cash', stakes: '1/2', profitLoss: 200)),
          isFalse);
      // Loss
      expect(
          f.matches(
              _session(gameType: 'cash', stakes: '2/5', profitLoss: -100)),
          isFalse);
    });

    test('date range + location — both must match', () {
      final f = const SessionFilter(
        dateFrom: '2026-05-01',
        dateTo: '2026-05-31',
        location: 'Playground Poker',
      );
      expect(
          f.matches(_session(date: '2026-05-15', location: 'Playground Poker')),
          isTrue);
      // Right location, wrong date
      expect(
          f.matches(_session(date: '2026-06-15', location: 'Playground Poker')),
          isFalse);
      // Right date, wrong location
      expect(f.matches(_session(date: '2026-05-15', location: 'Casino')),
          isFalse);
    });
  });

  // ── copyWith ─────────────────────────────────────────────────────────────────

  group('SessionFilter.copyWith', () {
    test('preserves unspecified fields', () {
      const f = SessionFilter(gameType: 'cash', stakes: '1/2');
      final updated = f.copyWith(stakes: '2/5');
      expect(updated.gameType, equals('cash'));
      expect(updated.stakes, equals('2/5'));
    });

    test('can clear a field by passing null', () {
      const f = SessionFilter(gameType: 'cash', stakes: '1/2');
      final cleared = f.copyWith(gameType: null);
      expect(cleared.gameType, isNull);
      expect(cleared.stakes, equals('1/2'));
    });
  });

  // ── empty filter matches everything ─────────────────────────────────────────

  group('empty filter', () {
    test('matches cash session', () {
      expect(const SessionFilter().matches(_session(gameType: 'cash')), isTrue);
    });

    test('matches tournament session', () {
      expect(const SessionFilter().matches(_session(gameType: 'tournament')),
          isTrue);
    });

    test('matches losing session', () {
      expect(const SessionFilter().matches(_session(profitLoss: -500)), isTrue);
    });
  });
}
