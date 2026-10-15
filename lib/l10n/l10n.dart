import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// `context.l10n.someKey` — the one access pattern for localized strings.
///
/// Read it in `build` / callbacks, never in `initState` (it depends on an
/// inherited widget). In async handlers capture `final l10n = context.l10n;`
/// BEFORE the first `await` so the existing `if (!mounted) return;` guard still
/// covers any SnackBar/dialog text that follows.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Native-language names for the language picker. Deliberately NOT localized —
/// a user who can't read the current language must still find their own.
/// Keep in sync with the `app_*.arb` files and
/// `android/app/src/main/res/xml/locales_config.xml`.
const Map<String, String> kLocaleEndonyms = {
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'it': 'Italiano',
  'nl': 'Nederlands',
};

/// Display name for a locale in the picker (endonym, falling back to the code
/// for a locale newer than this build knows).
String localeEndonym(Locale locale) =>
    kLocaleEndonyms[locale.languageCode] ?? locale.toLanguageTag();
