import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/screens/icm_calculator_screen.dart';
import 'package:tablelab/screens/variance_calculator_screen.dart';

import '../helpers/pump_app.dart';

/// The calculators render translated chrome in every shipped language and fit
/// a 360-wide phone — the Cash/Tournament SegmentedButton and the ICM column
/// headers are the overflow risks (nl/fr run ~30% longer than English).
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    final l10n = lookupAppLocalizations(locale);

    testWidgets('variance calculator in ${locale.toLanguageTag()} at 360×800',
        (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: VarianceCalculatorScreen(showScaffold: false)),
        locale: locale,
        size: const Size(360, 800),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.varianceModeCash), findsOneWidget);
      expect(find.text(l10n.varianceCalculate), findsOneWidget);
    });

    testWidgets('ICM calculator in ${locale.toLanguageTag()} at 360×800',
        (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: IcmCalculatorScreen(showScaffold: false)),
        locale: locale,
        size: const Size(360, 800),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.icmPlayers), findsOneWidget);
      expect(find.text(l10n.icmPlace1), findsOneWidget);
    });
  }
}
