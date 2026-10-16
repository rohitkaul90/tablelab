import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/services/ai_service.dart';
import 'package:tablelab/widgets/ai/ai_disclaimer_footer.dart';

import '../helpers/pump_app.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final nl = lookupAppLocalizations(const Locale('nl'));

  testWidgets('English UI: disclaimer only, no English-coaching note',
      (tester) async {
    await pumpApp(tester, const Scaffold(body: AiDisclaimerFooter()));
    expect(find.text(en.aiDisclaimer), findsOneWidget);
    expect(find.text(en.aiCoachingEnglishNote), findsNothing);
  });

  testWidgets('non-English UI: adds the "coaching is in English" note',
      (tester) async {
    await pumpApp(tester, const Scaffold(body: AiDisclaimerFooter()),
        locale: const Locale('nl'));
    expect(find.text(nl.aiDisclaimer), findsOneWidget);
    expect(find.text(nl.aiCoachingEnglishNote), findsOneWidget);
  });

  group('aiErrorText', () {
    const rateLimited = AiException(status: 429, message: 'server says no');
    const capacity = AiException(status: 503, message: 'server busy');
    const other = AiException(status: 500, message: 'boom');

    test('English keeps the server message, localizes the title', () {
      expect(aiErrorText(en, rateLimited),
          (title: en.aiDailyLimitTitle, body: 'server says no'));
      expect(aiErrorText(en, capacity),
          (title: en.aiAtCapacityTitle, body: 'server busy'));
      expect(aiErrorText(en, other),
          (title: en.aiAnalysisFailed, body: 'boom'));
    });

    test('other languages replace the English-only server text', () {
      expect(aiErrorText(nl, rateLimited),
          (title: nl.aiDailyLimitTitle, body: nl.aiErrorDailyLimitBody));
      expect(aiErrorText(nl, capacity),
          (title: nl.aiAtCapacityTitle, body: nl.aiErrorAtCapacityBody));
      expect(aiErrorText(nl, other),
          (title: nl.aiAnalysisFailed, body: nl.aiErrorGeneric));
    });

    test('a non-AI exception is the generic failure in every language', () {
      expect(aiErrorText(en, StateError('x')),
          (title: en.aiAnalysisFailed, body: en.aiErrorGeneric));
    });
  });
}
