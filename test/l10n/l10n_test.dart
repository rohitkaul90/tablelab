import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/l10n.dart';

import '../helpers/pump_app.dart';

/// End-to-end check of the l10n plumbing: the generated delegate, every
/// shipped ARB, the `context.l10n` extension and the shared test harness.
void main() {
  Widget probe() => Builder(
        builder: (context) => Scaffold(
          body: Text('${context.l10n.navHands}|${context.l10n.settingsLanguage}'),
        ),
      );

  testWidgets('defaults to English', (tester) async {
    await pumpApp(tester, probe());
    expect(find.text('Hands|Language'), findsOneWidget);
  });

  testWidgets('renders every supported locale from its ARB', (tester) async {
    const expected = {
      'es': 'Manos|Idioma',
      'fr': 'Mains|Langue',
      'it': 'Mani|Lingua',
      'nl': 'Handen|Taal',
    };
    for (final e in expected.entries) {
      await pumpApp(tester, probe(), locale: Locale(e.key));
      expect(find.text(e.value), findsOneWidget, reason: e.key);
    }
  });

  test('supported locales, endonyms and the Android locale config agree', () {
    final codes =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes, containsAll(['en', 'es', 'fr', 'it', 'nl']));
    expect(kLocaleEndonyms.keys.toSet(), codes,
        reason: 'kLocaleEndonyms must list exactly the supported locales');

    // Android 13's per-app language picker is driven by this XML, not by the
    // ARBs — a new locale that forgets it is silently absent from OS settings.
    final xml = File('android/app/src/main/res/xml/locales_config.xml')
        .readAsStringSync();
    final android = RegExp(r'android:name="([^"]+)"')
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .toSet();
    expect(android, codes,
        reason: 'locales_config.xml must list exactly the supported locales');
  });
}
