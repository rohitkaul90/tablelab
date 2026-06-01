import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/profile_model.dart';

void main() {
  // ── fromJson ─────────────────────────────────────────────────────────────────

  group('ProfileModel.fromJson', () {
    final Map<String, dynamic> fullJson = {
      'id': 'user-abc',
      'display_name': 'Rohit',
      'phone': '+1 416 555 0100',
      'home_city': 'Toronto',
      'preferred_game': 'cash',
      'preferred_stakes': '2/5',
      'playing_since': 2018,
      'hourly_rate_goal': 30.0,
      'starting_bankroll': 5000.0,
      'starting_bankroll_currency': 'CAD',
      'has_seen_onboarding': true,
    };

    test('parses all fields', () {
      final p = ProfileModel.fromJson(fullJson);
      expect(p.id, equals('user-abc'));
      expect(p.displayName, equals('Rohit'));
      expect(p.phone, equals('+1 416 555 0100'));
      expect(p.homeCity, equals('Toronto'));
      expect(p.preferredGame, equals('cash'));
      expect(p.preferredStakes, equals('2/5'));
      expect(p.playingSince, equals(2018));
      expect(p.hourlyRateGoal, equals(30.0));
      expect(p.startingBankroll, equals(5000.0));
      expect(p.startingBankrollCurrency, equals('CAD'));
      expect(p.hasSeenOnboarding, isTrue);
    });

    test('defaults currency to CAD when absent', () {
      final json = Map<String, dynamic>.from(fullJson)
        ..remove('starting_bankroll_currency');
      final p = ProfileModel.fromJson(json);
      expect(p.startingBankrollCurrency, equals('CAD'));
    });

    test('defaults hasSeenOnboarding to false when absent', () {
      final json = Map<String, dynamic>.from(fullJson)
        ..remove('has_seen_onboarding');
      final p = ProfileModel.fromJson(json);
      expect(p.hasSeenOnboarding, isFalse);
    });

    test('handles null optional fields gracefully', () {
      final minJson = {
        'id': 'min-user',
        'has_seen_onboarding': false,
      };
      final p = ProfileModel.fromJson(minJson);
      expect(p.id, equals('min-user'));
      expect(p.displayName, isNull);
      expect(p.phone, isNull);
      expect(p.homeCity, isNull);
      expect(p.preferredGame, isNull);
      expect(p.preferredStakes, isNull);
      expect(p.playingSince, isNull);
      expect(p.hourlyRateGoal, isNull);
      expect(p.startingBankroll, isNull);
    });

    test('coerces int numeric fields to double', () {
      final json = {...fullJson, 'starting_bankroll': 5000, 'hourly_rate_goal': 30};
      final p = ProfileModel.fromJson(json);
      expect(p.startingBankroll, isA<double>());
      expect(p.hourlyRateGoal, isA<double>());
    });
  });

  // ── toUpsert ──────────────────────────────────────────────────────────────────

  group('ProfileModel.toUpsert', () {
    test('round-trips all scalar fields', () {
      const p = ProfileModel(
        id: 'u1',
        displayName: 'Alice',
        homeCity: 'London',
        preferredGame: 'tournament',
        preferredStakes: '5/10',
        playingSince: 2015,
        hourlyRateGoal: 50.0,
        startingBankroll: 10000.0,
        startingBankrollCurrency: 'GBP',
        hasSeenOnboarding: true,
      );
      final map = p.toUpsert();
      expect(map['id'], equals('u1'));
      expect(map['display_name'], equals('Alice'));
      expect(map['home_city'], equals('London'));
      expect(map['preferred_game'], equals('tournament'));
      expect(map['preferred_stakes'], equals('5/10'));
      expect(map['playing_since'], equals(2015));
      expect(map['hourly_rate_goal'], equals(50.0));
      expect(map['starting_bankroll'], equals(10000.0));
      expect(map['starting_bankroll_currency'], equals('GBP'));
      expect(map['has_seen_onboarding'], isTrue);
    });

    test('includes updated_at timestamp string', () {
      const p = ProfileModel(id: 'u2');
      final map = p.toUpsert();
      expect(map['updated_at'], isA<String>());
      // Should be a parseable ISO 8601 timestamp
      expect(DateTime.tryParse(map['updated_at'] as String), isNotNull);
    });
  });

  // ── copyWith ──────────────────────────────────────────────────────────────────

  group('ProfileModel.copyWith', () {
    const base = ProfileModel(
      id: 'u3',
      displayName: 'Bob',
      homeCity: 'Toronto',
      preferredGame: 'cash',
      startingBankroll: 3000.0,
      startingBankrollCurrency: 'CAD',
      hasSeenOnboarding: true,
    );

    test('preserves unspecified fields', () {
      final updated = base.copyWith(homeCity: 'Montreal');
      expect(updated.id, equals('u3'));
      expect(updated.displayName, equals('Bob'));
      expect(updated.homeCity, equals('Montreal'));
      expect(updated.preferredGame, equals('cash'));
      expect(updated.startingBankroll, equals(3000.0));
      expect(updated.hasSeenOnboarding, isTrue);
    });

    test('clearPreferredGame sets preferredGame to null', () {
      final updated = base.copyWith(clearPreferredGame: true);
      expect(updated.preferredGame, isNull);
      expect(updated.homeCity, equals('Toronto'));
    });

    test('clearStartingBankroll sets startingBankroll to null', () {
      final updated = base.copyWith(clearStartingBankroll: true);
      expect(updated.startingBankroll, isNull);
    });

    test('hasSeenOnboarding is never changed by copyWith', () {
      // copyWith does not expose hasSeenOnboarding — only markOnboardingComplete() does.
      final updated = base.copyWith(displayName: 'Charlie');
      expect(updated.hasSeenOnboarding, isTrue);
    });

    test('update startingBankrollCurrency', () {
      final updated = base.copyWith(startingBankrollCurrency: 'USD');
      expect(updated.startingBankrollCurrency, equals('USD'));
    });
  });
}
