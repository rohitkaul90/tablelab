import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';
import 'package:tablelab/reads/tag_definitions.dart';
import 'package:tablelab/widgets/reads/quick_add_sheet.dart';

import '../helpers/pump_app.dart';

/// The Reads capture sheet renders every tag/group through l10n; in Dutch on a
/// narrow phone the chip Wraps must not overflow and the localized text (not
/// the English source) must be on screen.
void main() {
  testWidgets('QuickAddSheet renders in Dutch at phone width', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: QuickAddSheet(allPlayers: const [], onSaved: (_, _, _) async {}),
      ),
      locale: const Locale('nl'),
      size: const Size(360, 800),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final nl = lookupAppLocalizations(const Locale('nl'));
    // Header and an archetype chip are always in the first viewport.
    expect(find.text(nl.quickAddTitleNew), findsOneWidget);
    expect(find.text('New Player Read'), findsNothing);
    expect(find.text(tagDisplayName(nl, 'fish')), findsOneWidget);
    expect(find.text(nl.quickAddPlayerType.toUpperCase()), findsOneWidget);
  });
}
