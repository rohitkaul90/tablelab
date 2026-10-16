import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/screens/data_privacy_screen.dart';
import 'package:tablelab/screens/help_screen.dart';
import 'package:tablelab/screens/terms_of_service_screen.dart';

import '../helpers/pump_app.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final nl = lookupAppLocalizations(const Locale('nl'));

  testWidgets('Help renders its FAQ in Dutch', (tester) async {
    await pumpApp(tester, const HelpScreen(),
        locale: const Locale('nl'), size: const Size(360, 800));
    expect(tester.takeException(), isNull);
    expect(find.text(nl.helpTitle), findsOneWidget);
    expect(find.text(nl.faqGettingStarted1Q), findsOneWidget);
    expect(find.text(en.faqGettingStarted1Q), findsNothing);
  });

  testWidgets('Help still renders in English', (tester) async {
    await pumpApp(tester, const HelpScreen(), size: const Size(360, 800));
    expect(find.text('What is TableLab?'), findsOneWidget);
  });

  for (final (name, screen) in [
    ('Terms', const TermsOfServiceScreen()),
    ('Data & Privacy', const DataPrivacyScreen()),
  ]) {
    testWidgets('$name shows the English-only notice in Dutch', (tester) async {
      await pumpApp(tester, screen, locale: const Locale('nl'));
      expect(find.text(nl.legalEnglishOnlyNotice), findsOneWidget);
    });

    testWidgets('$name hides the notice in English', (tester) async {
      await pumpApp(tester, screen);
      expect(find.text(en.legalEnglishOnlyNotice), findsNothing);
    });
  }
}
