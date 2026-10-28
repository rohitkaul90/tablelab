import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/providers/providers.dart';
import 'package:tablelab/screens/log_session_screen.dart';

import '../helpers/pump_app.dart';

/// Narrow-phone (360×800) render of the manual session form in each shipped
/// locale: no overflow/layout exception, and the translated chrome is on
/// screen. Dutch and French run ~30% longer than English, so this is the
/// cheapest overflow regression check for the longest form in the app.
void main() {
  Future<void> pumpForm(WidgetTester tester, Locale locale) => pumpApp(
        tester,
        const LogSessionScreen(),
        locale: locale,
        overrides: [
          sessionsProvider.overrideWith((ref) async => <SessionModel>[]),
        ],
        size: const Size(360, 800),
      );

  testWidgets('renders in English with the expected labels', (tester) async {
    await pumpForm(tester, const Locale('en'));
    expect(tester.takeException(), isNull);
    // The form is a lazy ListView, so only the top of the form is built at
    // 800dp — assert on the app bar and the game-type toggle, not the footer.
    expect(find.text('Log Session'), findsOneWidget);
    expect(find.text('Cash Game'), findsOneWidget);
    expect(find.text('Tournament'), findsOneWidget);
  });

  for (final code in ['es', 'es-419', 'fr', 'it', 'nl', 'ja', 'ko', 'zh-Hant']) {
    testWidgets('renders in $code on a 360dp phone without overflow',
        (tester) async {
      await pumpForm(tester, localeFromLanguageTag(code));
      expect(tester.takeException(), isNull);
      // The English title must be gone — the ARB for this locale is in use.
      expect(find.text('Log Session'), findsNothing);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
    });
  }
}
