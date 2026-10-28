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
      await pumpApp(tester, probe(), locale: localeFromLanguageTag(e.key));
      expect(find.text(e.value), findsOneWidget, reason: e.key);
    }
    // Every shipped ARB needs a spot check above — a new locale that forgets
    // one is caught here, not at the store.
    expect(
      AppLocalizations.supportedLocales
          .map((l) => l.toLanguageTag())
          .where((t) => t != 'en')
          .toSet(),
      expected.keys.toSet(),
      reason: 'add a spot check for each new ARB',
    );
  });

  test('supported locales, endonyms and the platform locale lists agree', () {
    // Compared as full BCP-47 tags (`zh-Hant`, `es-419`), not bare language
    // codes — two Spanish variants or two Chinese scripts must stay distinct.
    final tags =
        AppLocalizations.supportedLocales.map((l) => l.toLanguageTag()).toSet();
    expect(tags, containsAll(['en', 'es', 'fr', 'it', 'nl']));
    expect(kLocaleEndonyms.keys.toSet(), tags,
        reason: 'kLocaleEndonyms must list exactly the supported locales');

    // Android 13's per-app language picker is driven by this XML, not by the
    // ARBs — a new locale that forgets it is silently absent from OS settings.
    final xml = File('android/app/src/main/res/xml/locales_config.xml')
        .readAsStringSync();
    final android = RegExp(r'android:name="([^"]+)"')
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .toSet();
    expect(android, tags,
        reason: 'locales_config.xml must list exactly the supported locales');

    // iOS: the App Store "Languages" line and the per-app language setting
    // come from CFBundleLocalizations in the shipped build.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final block = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(block, isNotNull, reason: 'Info.plist has no CFBundleLocalizations');
    final ios = RegExp(r'<string>([^<]+)</string>')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
    expect(ios, tags,
        reason:
            'Info.plist CFBundleLocalizations must list exactly the supported locales');
  });
}
