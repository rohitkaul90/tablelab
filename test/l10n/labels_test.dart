import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/l10n/labels.dart';
import 'package:tablelab/utils/helpers.dart';

/// The stable analytics keys (helpers.dart enums/ids) map to the English text
/// the Stats tabs showed before localization, and to a different rendering in
/// another locale — proving keys and words are separated.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final nl = lookupAppLocalizations(const Locale('nl'));

  test('bucket labels reproduce the legacy English text', () {
    expect(buyInBucketLabel(en, BuyInBucket.under50, 'USD'), r'< $50');
    expect(buyInBucketLabel(en, BuyInBucket.from200to500, 'USD'), r'$200–$500');
    // Band edges are USD amounts converted into the display currency.
    // Non-USD edges are converted then rounded to readable amounts.
    expect(buyInBucketLabel(en, BuyInBucket.over500, 'EUR'), '> €500');
    expect(buyInBucketLabel(en, BuyInBucket.from50to100, 'EUR'), '€50–€100');
    expect(fieldSizeBucketLabel(en, FieldSizeBucket.medium), 'Medium (50–200)');
    expect(timeOfDayBucketLabel(en, TimeOfDayBucket.evening), 'Evening (6pm–11pm)');
    expect(timeOfDayBucketLabel(en, TimeOfDayBucket.lateNight, short: true),
        'Late Night');
    expect(sessionLengthBucketLabel(en, SessionLengthBucket.under2h), '< 2 hours');
    expect(gameTypeKeyLabel(en, 'cash'), 'Cash Game');
    expect(gameTypeKeyLabel(en, 'tournament'), 'Tournament');
    expect(gameTypeKeyLabel(en, 'plo5'), 'plo5');
    expect(tableQualityKeyLabel(en, 1), 'Very Tough');
    expect(tableQualityKeyLabel(en, null), 'Not rated');
    expect(venueLabel(en, 'online'), 'Online');
    expect(venueLabel(en, 'live'), 'Live');
  });

  test('every enum value has a label in every shipped locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final b in BuyInBucket.values) {
        expect(buyInBucketLabel(l10n, b, 'USD'), isNotEmpty, reason: '$locale $b');
      }
      for (final b in FieldSizeBucket.values) {
        expect(fieldSizeBucketLabel(l10n, b), isNotEmpty, reason: '$locale $b');
      }
      for (final b in TimeOfDayBucket.values) {
        expect(timeOfDayBucketLabel(l10n, b), isNotEmpty, reason: '$locale $b');
        expect(timeOfDayBucketLabel(l10n, b, short: true), isNotEmpty);
      }
      for (final b in SessionLengthBucket.values) {
        expect(sessionLengthBucketLabel(l10n, b), isNotEmpty, reason: '$locale $b');
      }
    }
  });

  test('a non-English locale renders different words for the same key', () {
    expect(gameTypeKeyLabel(nl, 'tournament'), isNot('Tournament'));
    expect(venueLabel(nl, 'live'), isNotEmpty);
  });

  test('weekday labels follow the AppLocalizations locale', () async {
    await initializeDateFormatting('en');
    expect(weekdayShortLabel(en, 1), 'Mon');
    expect(weekdayShortLabel(en, 7), 'Sun');

    await initializeDateFormatting('fr');
    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(weekdayShortLabel(fr, 1).toLowerCase(), startsWith('lun'));
  });
}
