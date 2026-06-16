import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/utils/helpers.dart';
import 'package:tablelab/models/session_model.dart';

void main() {
  // ── playedMinutes ────────────────────────────────────────────────────────────

  group('playedMinutes', () {
    test('subtracts breaks from gross', () {
      expect(playedMinutes(240, 30), equals(210));
      expect(playedMinutes(60, 0), equals(60));
    });
    test('floors at zero when break exceeds gross', () {
      expect(playedMinutes(120, 150), equals(0));
      expect(playedMinutes(0, 0), equals(0));
    });
  });

  // ── parseBBFromStakes ────────────────────────────────────────────────────────

  group('parseBBFromStakes', () {
    test('parses standard NL stakes', () {
      expect(parseBBFromStakes('1/2'), equals(2.0));
      expect(parseBBFromStakes('2/5'), equals(5.0));
      expect(parseBBFromStakes('5/10'), equals(10.0));
      expect(parseBBFromStakes('25/50'), equals(50.0));
    });

    test('strips dollar signs', () {
      expect(parseBBFromStakes(r'$1/$2'), equals(2.0));
      expect(parseBBFromStakes(r'$2/$5'), equals(5.0));
    });

    test('handles spaces around slash', () {
      expect(parseBBFromStakes('1 / 2'), equals(2.0));
      expect(parseBBFromStakes('2 / 5'), equals(5.0));
    });

    test('returns null for unrecognisable format', () {
      expect(parseBBFromStakes(''), isNull);
      expect(parseBBFromStakes('N/A'), isNull);
      expect(parseBBFromStakes('100'), isNull);
    });

    test('handles decimal stakes', () {
      expect(parseBBFromStakes('0.5/1'), equals(1.0));
      expect(parseBBFromStakes('0.25/0.5'), equals(0.5));
    });

    test('takes the big blind (2nd value) from a 3-blind / straddle game', () {
      expect(parseBBFromStakes(r'$2/$5/$10'), equals(5.0));
      expect(parseBBFromStakes('1/2/4'), equals(2.0));
    });

    test('handles non-dollar currency symbols', () {
      expect(parseBBFromStakes('£2/£5'), equals(5.0));
      expect(parseBBFromStakes('€1/€2'), equals(2.0));
      expect(parseBBFromStakes('₹100/₹200'), equals(200.0));
    });

    test('handles other separators', () {
      expect(parseBBFromStakes('1-2'), equals(2.0));
      expect(parseBBFromStakes('2-5'), equals(5.0));
    });

    test('ignores trailing game-type labels', () {
      expect(parseBBFromStakes('1/2 NLHE'), equals(2.0));
      expect(parseBBFromStakes(r'$2/$5 NL'), equals(5.0));
      expect(parseBBFromStakes('5/10 PLO'), equals(10.0));
    });

    test('handles k-suffix and comma decimals', () {
      expect(parseBBFromStakes('1k/2k'), equals(2000.0));
      expect(parseBBFromStakes('2,5/5'), equals(5.0));
      expect(parseBBFromStakes('1/2,5'), equals(2.5));
    });

    test('parses online cap notation (NLxxx → BB = number/100)', () {
      expect(parseBBFromStakes('NL100'), equals(1.0));
      expect(parseBBFromStakes('200NL'), equals(2.0));
      expect(parseBBFromStakes('PLO50'), equals(0.5));
      expect(parseBBFromStakes('nl1000'), equals(10.0));
      expect(parseBBFromStakes('NL2'), closeTo(0.02, 1e-9));
    });

    test('bare single number and pure text are unparseable', () {
      expect(parseBBFromStakes('200'), isNull);
      expect(parseBBFromStakes('Microstakes'), isNull);
    });
  });

  // ── parseBlindsFromStakes ────────────────────────────────────────────────────

  group('parseBlindsFromStakes', () {
    test('returns both blinds for standard stakes', () {
      expect(parseBlindsFromStakes('1/2'), equals((1.0, 2.0)));
      expect(parseBlindsFromStakes('2/5'), equals((2.0, 5.0)));
      expect(parseBlindsFromStakes('25/50'), equals((25.0, 50.0)));
    });

    test('strips currency symbols and handles separators', () {
      expect(parseBlindsFromStakes(r'$2/$5'), equals((2.0, 5.0)));
      expect(parseBlindsFromStakes('£2/£5'), equals((2.0, 5.0)));
      expect(parseBlindsFromStakes('1-2'), equals((1.0, 2.0)));
    });

    test('SB is first, BB is second in a 3-blind / straddle game', () {
      expect(parseBlindsFromStakes(r'$2/$5/$10'), equals((2.0, 5.0)));
    });

    test('cap notation derives SB as half the BB', () {
      expect(parseBlindsFromStakes('NL100'), equals((0.5, 1.0)));
      expect(parseBlindsFromStakes('200NL'), equals((1.0, 2.0)));
    });

    test('the BB always matches parseBBFromStakes', () {
      for (final s in ['1/2', r'$2/$5', '1-2', 'NL100', '1k/2k', '2,5/5']) {
        expect(parseBlindsFromStakes(s)?.$2, equals(parseBBFromStakes(s)),
            reason: s);
      }
    });

    test('returns null for unparseable input', () {
      expect(parseBlindsFromStakes(''), isNull);
      expect(parseBlindsFromStakes('200'), isNull);
      expect(parseBlindsFromStakes('N/A'), isNull);
    });
  });

  // ── calcBB100 ────────────────────────────────────────────────────────────────

  group('calcBB100', () {
    SessionModel makeSession({
      required double profitLoss,
      required String stakes,
      required int durationMinutes,
      int? handsPerHour,
      String gameType = 'cash',
    }) {
      return SessionModel(
        id: 'test',
        date: '2026-01-01',
        stakes: stakes,
        gameType: gameType,
        buyIn: 200,
        cashOut: 200 + profitLoss,
        profitLoss: profitLoss,
        startTime: '18:00',
        endTime: '22:00',
        durationMinutes: durationMinutes,
        createdAt: '2026-01-01T18:00:00Z',
        currency: 'USD',
        handsPerHour: handsPerHour,
      );
    }

    test('returns null for empty session list', () {
      expect(calcBB100([]), isNull);
    });

    test('returns null when no cash sessions', () {
      final sessions = [
        makeSession(profitLoss: 100, stakes: '1/2', durationMinutes: 240, gameType: 'tournament'),
      ];
      expect(calcBB100(sessions), isNull);
    });

    test('returns null when BB cannot be parsed', () {
      final sessions = [
        makeSession(profitLoss: 100, stakes: 'N/A', durationMinutes: 240),
      ];
      expect(calcBB100(sessions), isNull);
    });

    test('calculates correct BB/100 for single session', () {
      // 4h session at 25 hands/hr → 100 hands; +$100 at 1/2 → +50BB → +50 BB/100
      final sessions = [
        makeSession(
          profitLoss: 100,
          stakes: '1/2',
          durationMinutes: 240,
          handsPerHour: 25,
        ),
      ];
      final result = calcBB100(sessions);
      expect(result, isNotNull);
      expect(result!, closeTo(50.0, 0.01));
    });

    test('uses default 25 hands/hr when handsPerHour is null', () {
      // Same scenario, handsPerHour not recorded
      final sessions = [
        makeSession(profitLoss: 100, stakes: '1/2', durationMinutes: 240),
      ];
      final result = calcBB100(sessions);
      expect(result, isNotNull);
      expect(result!, closeTo(50.0, 0.01));
    });

    test('aggregates across multiple sessions', () {
      // Session 1: +$100 in 4h at 1/2 → +50BB in 100 hands
      // Session 2: -$50  in 4h at 1/2 → -25BB in 100 hands
      // Net: +25BB in 200 hands → +12.5 BB/100
      final sessions = [
        makeSession(profitLoss: 100, stakes: '1/2', durationMinutes: 240, handsPerHour: 25),
        makeSession(profitLoss: -50, stakes: '1/2', durationMinutes: 240, handsPerHour: 25),
      ];
      final result = calcBB100(sessions);
      expect(result, isNotNull);
      expect(result!, closeTo(12.5, 0.01));
    });

    test('excludes tournament sessions from BB/100', () {
      final sessions = [
        makeSession(profitLoss: 100, stakes: '1/2', durationMinutes: 240, handsPerHour: 25),
        makeSession(profitLoss: 1000, stakes: '1/2', durationMinutes: 240, gameType: 'tournament'),
      ];
      // Only the cash session counts
      final result = calcBB100(sessions);
      expect(result, isNotNull);
      expect(result!, closeTo(50.0, 0.01));
    });
  });

  // ── formatPL ─────────────────────────────────────────────────────────────────

  group('formatPL', () {
    test('formats positive amount with + sign', () {
      expect(formatPL(100), equals(r'+$100'));
      expect(formatPL(1500), equals(r'+$1,500'));
    });

    test('formats negative amount with - sign', () {
      expect(formatPL(-100), equals(r'-$100'));
      expect(formatPL(-1500), equals(r'-$1,500'));
    });

    test('formats zero as positive', () {
      expect(formatPL(0), equals(r'+$0'));
    });

    test('uses provided currency symbol', () {
      expect(formatPL(100, '£'), equals('+£100'));
      expect(formatPL(-50, '€'), equals('-€50'));
    });

    test('rounds to nearest dollar', () {
      expect(formatPL(99.6), equals(r'+$100'));
      expect(formatPL(-99.4), equals(r'-$99'));
    });
  });

  // ── currencySymbol ───────────────────────────────────────────────────────────

  group('currencySymbol', () {
    test('returns correct symbols for known currencies', () {
      expect(currencySymbol('USD'), equals(r'$'));
      expect(currencySymbol('CAD'), equals(r'CA$'));
      expect(currencySymbol('GBP'), equals('£'));
      expect(currencySymbol('EUR'), equals('€'));
      expect(currencySymbol('AUD'), equals(r'A$'));
      expect(currencySymbol('INR'), equals('₹'));
    });

    test('returns NZ\$ for NZD', () {
      expect(currencySymbol('NZD'), equals(r'NZ$'));
    });

    test('defaults to dollar sign for unknown currency', () {
      expect(currencySymbol('XYZ'), equals(r'$'));
    });
  });

  // ── convertCurrency ──────────────────────────────────────────────────────────

  group('convertCurrency', () {
    test('returns same amount for same currency', () {
      expect(convertCurrency(100, 'USD', 'USD'), equals(100.0));
    });

    test('converts USD to CAD approximately correctly', () {
      final result = convertCurrency(100, 'USD', 'CAD');
      expect(result, closeTo(138.0, 1.0));
    });

    test('converts CAD to USD approximately correctly', () {
      final result = convertCurrency(138, 'CAD', 'USD');
      expect(result, closeTo(100.0, 1.0));
    });

    test('round-trips within rounding tolerance', () {
      final cad = convertCurrency(100, 'USD', 'CAD');
      final usd = convertCurrency(cad, 'CAD', 'USD');
      expect(usd, closeTo(100.0, 0.01));
    });

    test('unknown from-currency falls back to 1.0 rate', () {
      // XYZ is treated as 1:1 with USD
      expect(convertCurrency(100, 'XYZ', 'USD'), closeTo(100.0, 0.01));
    });

    test('unknown to-currency falls back to 1.0 rate', () {
      expect(convertCurrency(100, 'USD', 'XYZ'), closeTo(100.0, 0.01));
    });
  });

  // ── formatDuration ───────────────────────────────────────────────────────────

  group('formatDuration', () {
    test('shows only minutes when under an hour', () {
      expect(formatDuration(45), equals('45m'));
    });

    test('shows only hours when no remainder', () {
      expect(formatDuration(120), equals('2h'));
    });

    test('shows hours and minutes', () {
      expect(formatDuration(150), equals('2h 30m'));
      expect(formatDuration(95), equals('1h 35m'));
    });
  });

  // ── calcDurationMinutes ──────────────────────────────────────────────────────

  group('calcDurationMinutes', () {
    test('calculates same-day duration', () {
      expect(calcDurationMinutes('18:00', '22:30'), equals(270));
    });

    test('handles overnight sessions', () {
      expect(calcDurationMinutes('22:00', '02:00'), equals(240));
    });

    test('returns zero for invalid time strings', () {
      expect(calcDurationMinutes('bad', '22:00'), equals(0));
    });

    test('returns zero when time has colon but non-numeric parts', () {
      // splits into 2 parts, but the parts fail int.tryParse
      expect(calcDurationMinutes('1a:30', '22:00'), equals(0));
      expect(calcDurationMinutes('18:00', '10:bb'), equals(0));
    });
  });

  // ── supportedDisplayCurrencies ───────────────────────────────────────────────

  group('supportedDisplayCurrencies', () {
    test('is sorted and contains the major currencies', () {
      final list = supportedDisplayCurrencies;
      expect(list, containsAll(['USD', 'CAD', 'GBP', 'EUR', 'INR']));
      final sorted = [...list]..sort();
      expect(list, equals(sorted));
    });
  });

  // ── isTournamentType ─────────────────────────────────────────────────────────

  group('isTournamentType', () {
    test('identifies tournament and sit_and_go', () {
      expect(isTournamentType('tournament'), isTrue);
      expect(isTournamentType('sit_and_go'), isTrue);
    });

    test('returns false for cash games', () {
      expect(isTournamentType('cash'), isFalse);
    });
  });

  // ── fieldSizeBucket ──────────────────────────────────────────────────────────

  group('fieldSizeBucket', () {
    test('returns empty string for null or zero', () {
      expect(fieldSizeBucket(null), equals(''));
      expect(fieldSizeBucket(0), equals(''));
    });

    test('buckets correctly', () {
      expect(fieldSizeBucket(20), equals('Small (<50)'));
      expect(fieldSizeBucket(100), equals('Medium (50–200)'));
      expect(fieldSizeBucket(300), equals('Large (200–500)'));
      expect(fieldSizeBucket(1000), equals('Massive (500+)'));
    });
  });

  // ── currencyFromCountry ──────────────────────────────────────────────────────

  group('currencyFromCountry', () {
    test('returns null for null or empty', () {
      expect(currencyFromCountry(null), isNull);
      expect(currencyFromCountry(''), isNull);
    });

    test('returns correct currency for known countries', () {
      expect(currencyFromCountry('Canada'), equals('CAD'));
      expect(currencyFromCountry('USA'), equals('USD'));
      expect(currencyFromCountry('United States'), equals('USD'));
      expect(currencyFromCountry('online'), equals('USD'));
      expect(currencyFromCountry('United Kingdom'), equals('GBP'));
      expect(currencyFromCountry('Australia'), equals('AUD'));
      expect(currencyFromCountry('New Zealand'), equals('NZD'));
      expect(currencyFromCountry('India'), equals('INR'));
      expect(currencyFromCountry('France'), equals('EUR'));
      expect(currencyFromCountry('Germany'), equals('EUR'));
    });

    test('is case-insensitive', () {
      expect(currencyFromCountry('CANADA'), equals('CAD'));
      expect(currencyFromCountry('canada'), equals('CAD'));
    });

    test('returns null for unknown country', () {
      expect(currencyFromCountry('Mars'), isNull);
    });
  });

  // ── formatAmount ─────────────────────────────────────────────────────────────

  group('formatAmount', () {
    test('formats USD with dollar sign', () {
      expect(formatAmount(100, 'USD'), equals(r'$100'));
      expect(formatAmount(1500, 'USD'), equals(r'$1,500'));
    });

    test('formats CAD with CA\$ prefix', () {
      expect(formatAmount(200, 'CAD'), equals(r'CA$200'));
    });

    test('formats GBP with pound sign', () {
      expect(formatAmount(50, 'GBP'), equals('£50'));
    });

    test('rounds to nearest whole unit', () {
      expect(formatAmount(99.6, 'USD'), equals(r'$100'));
      expect(formatAmount(99.4, 'USD'), equals(r'$99'));
    });
  });

  // ── formatPLWithCurrency ─────────────────────────────────────────────────────

  group('formatPLWithCurrency', () {
    test('positive amount with currency symbol', () {
      expect(formatPLWithCurrency(100, 'USD'), equals(r'+$100'));
      expect(formatPLWithCurrency(100, 'GBP'), equals('+£100'));
    });

    test('negative amount with currency symbol', () {
      expect(formatPLWithCurrency(-50, 'EUR'), equals('-€50'));
    });
  });

  // ── calcROI ──────────────────────────────────────────────────────────────────

  group('calcROI', () {
    test('returns correct ROI percentage', () {
      expect(calcROI(100, 200), closeTo(50.0, 0.001));
      expect(calcROI(-50, 100), closeTo(-50.0, 0.001));
    });

    test('returns 0 when buyIn is zero', () {
      expect(calcROI(100, 0), equals(0.0));
    });

    test('returns 0 when buyIn is negative', () {
      expect(calcROI(100, -100), equals(0.0));
    });

    test('100% ROI when profit equals buy-in', () {
      expect(calcROI(200, 200), closeTo(100.0, 0.001));
    });
  });

  // ── formatROI ────────────────────────────────────────────────────────────────

  group('formatROI', () {
    test('positive ROI has + prefix', () {
      expect(formatROI(50.0), equals('+50%'));
      expect(formatROI(0.0), equals('+0%'));
    });

    test('negative ROI has - prefix', () {
      expect(formatROI(-25.0), equals('-25%'));
    });

    test('rounds to whole number', () {
      expect(formatROI(33.7), equals('+34%'));
    });
  });

  // ── tournamentBuyInBucket ────────────────────────────────────────────────────

  group('tournamentBuyInBucket', () {
    test('buckets low buy-ins', () {
      expect(tournamentBuyInBucket(20), equals(r'< $50'));
      expect(tournamentBuyInBucket(49), equals(r'< $50'));
    });

    test('buckets mid-range buy-ins', () {
      expect(tournamentBuyInBucket(50), equals(r'$50–$100'));
      expect(tournamentBuyInBucket(75), equals(r'$50–$100'));
      expect(tournamentBuyInBucket(100), equals(r'$100–$200'));
      expect(tournamentBuyInBucket(150), equals(r'$100–$200'));
    });

    test('buckets high buy-ins', () {
      expect(tournamentBuyInBucket(200), equals(r'$200–$500'));
      expect(tournamentBuyInBucket(499), equals(r'$200–$500'));
      expect(tournamentBuyInBucket(500), equals(r'> $500'));
      expect(tournamentBuyInBucket(1000), equals(r'> $500'));
    });
  });

  // ── isSessionItm ─────────────────────────────────────────────────────────────

  group('isSessionItm', () {
    test('ITM when prizeWon > 0', () {
      expect(isSessionItm(500, -100), isTrue);
    });

    test('not ITM when prizeWon == 0', () {
      expect(isSessionItm(0, -100), isFalse);
    });

    test('not ITM when prizeWon < 0 (should not happen, but safe)', () {
      expect(isSessionItm(-1, 100), isFalse);
    });

    test('falls back to profitLoss > 0 when prizeWon is null', () {
      expect(isSessionItm(null, 50), isTrue);
      expect(isSessionItm(null, -50), isFalse);
      expect(isSessionItm(null, 0), isFalse);
    });
  });

  // ── gameTypeLabel ────────────────────────────────────────────────────────────

  group('gameTypeLabel', () {
    test('known types return labels', () {
      expect(gameTypeLabel('cash'), equals('Cash Game'));
      expect(gameTypeLabel('tournament'), equals('Tournament'));
      expect(gameTypeLabel('sit_and_go'), equals('Tournament'));
    });

    test('unknown type returns raw value', () {
      expect(gameTypeLabel('plo5'), equals('plo5'));
    });
  });

  // ── tableQualityLabel ────────────────────────────────────────────────────────

  group('tableQualityLabel', () {
    test('returns labels for ratings 1–5', () {
      expect(tableQualityLabel(1), equals('Very Tough'));
      expect(tableQualityLabel(2), equals('Tough'));
      expect(tableQualityLabel(3), equals('Average'));
      expect(tableQualityLabel(4), equals('Soft'));
      expect(tableQualityLabel(5), equals('Very Soft'));
    });

    test('returns Not rated for null or out-of-range', () {
      expect(tableQualityLabel(null), equals('Not rated'));
      expect(tableQualityLabel(0), equals('Not rated'));
      expect(tableQualityLabel(6), equals('Not rated'));
    });
  });

  // ── timeOfDayBucket ──────────────────────────────────────────────────────────

  group('timeOfDayBucket', () {
    test('morning bucket', () {
      expect(timeOfDayBucket('06:00'), equals('Morning (6am–12pm)'));
      expect(timeOfDayBucket('11:59'), equals('Morning (6am–12pm)'));
    });

    test('afternoon bucket', () {
      expect(timeOfDayBucket('12:00'), equals('Afternoon (12pm–6pm)'));
      expect(timeOfDayBucket('17:30'), equals('Afternoon (12pm–6pm)'));
    });

    test('evening bucket', () {
      expect(timeOfDayBucket('18:00'), equals('Evening (6pm–11pm)'));
      expect(timeOfDayBucket('22:59'), equals('Evening (6pm–11pm)'));
    });

    test('late night bucket', () {
      expect(timeOfDayBucket('23:00'), equals('Late Night (11pm–6am)'));
      expect(timeOfDayBucket('02:00'), equals('Late Night (11pm–6am)'));
      expect(timeOfDayBucket('05:59'), equals('Late Night (11pm–6am)'));
    });
  });

  // ── sessionLengthBucket ──────────────────────────────────────────────────────

  group('sessionLengthBucket', () {
    test('short sessions', () {
      expect(sessionLengthBucket(60), equals('< 2 hours'));
      expect(sessionLengthBucket(119), equals('< 2 hours'));
    });

    test('medium sessions', () {
      expect(sessionLengthBucket(120), equals('2–4 hours'));
      expect(sessionLengthBucket(239), equals('2–4 hours'));
    });

    test('long sessions', () {
      expect(sessionLengthBucket(240), equals('4–6 hours'));
      expect(sessionLengthBucket(359), equals('4–6 hours'));
    });

    test('marathon sessions', () {
      expect(sessionLengthBucket(360), equals('> 6 hours'));
      expect(sessionLengthBucket(720), equals('> 6 hours'));
    });
  });

  // ── dayOfWeekLabel ───────────────────────────────────────────────────────────

  group('dayOfWeekLabel', () {
    test('returns correct day abbreviations', () {
      expect(dayOfWeekLabel('2026-05-31'), equals('Sun')); // 2026-05-31 is a Sunday
      expect(dayOfWeekLabel('2026-06-01'), equals('Mon'));
      expect(dayOfWeekLabel('2026-06-06'), equals('Sat'));
    });

    test('falls back to today on invalid date', () {
      // Should not throw — just returns some valid day
      expect(() => dayOfWeekLabel('invalid'), returnsNormally);
    });
  });

  // ── monthLabel ───────────────────────────────────────────────────────────────

  group('monthLabel', () {
    test('returns month and year', () {
      expect(monthLabel('2026-01-15'), equals('Jan 2026'));
      expect(monthLabel('2026-12-31'), equals('Dec 2026'));
      expect(monthLabel('2025-06-01'), equals('Jun 2025'));
    });

    test('does not throw on invalid date', () {
      expect(() => monthLabel('bad-date'), returnsNormally);
    });
  });

  // ── formatBB100 ──────────────────────────────────────────────────────────────

  group('formatBB100', () {
    test('positive value has + prefix', () {
      expect(formatBB100(12.0), equals('+12'));
      expect(formatBB100(0.0), equals('+0'));
    });

    test('negative value has - prefix', () {
      expect(formatBB100(-8.0), equals('-8'));
    });

    test('rounds to nearest integer', () {
      expect(formatBB100(12.6), equals('+13'));
      expect(formatBB100(-3.4), equals('-3'));
    });
  });

  // ── tableSizeLabel ───────────────────────────────────────────────────────────

  group('tableSizeLabel', () {
    test('labels heads-up specially', () {
      expect(tableSizeLabel(2), equals('Heads-up (2)'));
    });

    test('labels common ring sizes', () {
      expect(tableSizeLabel(6), equals('6-max'));
      expect(tableSizeLabel(9), equals('9-max (full ring)'));
    });

    test('falls back to N-handed for other sizes', () {
      expect(tableSizeLabel(3), equals('3-handed'));
      expect(tableSizeLabel(5), equals('5-handed'));
      expect(tableSizeLabel(8), equals('8-handed'));
    });
  });

  // ── formatHours ──────────────────────────────────────────────────────────────

  group('formatHours', () {
    test('rounds to a whole number with a thousands separator', () {
      expect(formatHours(3389.1), equals('3,389h'));
      expect(formatHours(999.6), equals('1,000h'));
      expect(formatHours(0), equals('0h'));
      expect(formatHours(45.4), equals('45h'));
    });
  });
}
