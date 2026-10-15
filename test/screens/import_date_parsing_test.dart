import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tablelab/screens/import_mapping_screen.dart';

/// Imported CSV/Excel values carry English month names and AM/PM markers no
/// matter which language the UI runs in. These must keep parsing when
/// `Intl.defaultLocale` is a non-English UI language (locale_provider.dart
/// sets it) — the parsers are pinned to en_US for that reason.
void main() {
  for (final uiLocale in ['en', 'es', 'fr', 'nl']) {
    group('under UI locale $uiLocale', () {
      test('English month names still parse', () {
        Intl.withLocale(uiLocale, () {
          expect(parseImportDate('Jan 5, 2024'), '2024-01-05');
          expect(parseImportDate('5 Mar 2023'), '2023-03-05');
          expect(parseImportDate('December 31, 2022'), '2022-12-31');
          expect(parseImportDate('Mon, Jan 5, 2024'), '2024-01-05');
        });
      });

      test('numeric and ISO dates still parse', () {
        Intl.withLocale(uiLocale, () {
          expect(parseImportDate('2024-01-05'), '2024-01-05');
          expect(parseImportDate('01/05/2024'), '2024-01-05');
          expect(parseImportDate('garbage'), isNull);
        });
      });

      test('AM/PM times still parse', () {
        Intl.withLocale(uiLocale, () {
          expect(normalizeImportTime('7:30 PM'), '19:30');
          expect(normalizeImportTime('7:30 AM'), '07:30');
          expect(normalizeImportTime('19:30'), '19:30');
          expect(normalizeImportTime(''), '00:00');
        });
      });
    });
  }
}
