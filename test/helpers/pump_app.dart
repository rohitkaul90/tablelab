import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/l10n/l10n.dart';

/// Wraps [home] the way `PokerTrackerApp` does — `ProviderScope` + a
/// `MaterialApp` carrying the localization delegates — so any screen that
/// reads `context.l10n` can be pumped in a test. `AppLocalizations.of` is a
/// NON-nullable getter (l10n.yaml `nullable-getter: false`), so pumping a
/// localized screen in a bare `MaterialApp` throws; use this instead.
///
/// The generated delegate loads synchronously, so no extra pump is needed
/// before asserting on text. Existing English `find.text(...)` assertions keep
/// passing under the default `en` locale.
Widget wrapApp(
  Widget home, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      // Same chrome-locale mapping as PokerTrackerApp (bare zh → zh_Hant_TW).
      localeResolutionCallback: (device, _) => materialLocaleFor(device ?? locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

/// Pumps [home] via [wrapApp]. [size] sets the logical viewport (device pixel
/// ratio 1.0) and resets it on teardown — pass e.g. `const Size(360, 800)` for
/// a narrow-phone overflow check.
Future<void> pumpApp(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(wrapApp(home, locale: locale, overrides: overrides));
  await tester.pump();
}
