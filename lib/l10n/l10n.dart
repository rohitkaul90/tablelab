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

/// Native-language names for the language picker, keyed by BCP-47 language
/// tag (`Locale.toLanguageTag()`: `zh-Hant`, `es-419`). Deliberately NOT
/// localized — a user who can't read the current language must still find
/// their own. Keep in sync with the `app_*.arb` files,
/// `android/app/src/main/res/xml/locales_config.xml` and
/// `ios/Runner/Info.plist` `CFBundleLocalizations` (test-enforced).
const Map<String, String> kLocaleEndonyms = {
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'it': 'Italiano',
  'nl': 'Nederlands',
};

/// Display name for a locale in the picker (endonym, falling back to the tag
/// for a locale newer than this build knows).
String localeEndonym(Locale locale) =>
    kLocaleEndonyms[locale.toLanguageTag()] ?? locale.toLanguageTag();

/// Parses a BCP-47 / POSIX tag (`zh-Hant`, `es_419`, `fr`, `zh-Hant-TW`)
/// back into a [Locale]: a 4-letter subtag is the script, a 2-letter or
/// 3-digit one the region. Pure; used for the persisted language preference.
Locale localeFromLanguageTag(String tag) {
  final parts = tag.split(RegExp('[_-]'));
  final language = parts.first;
  String? script;
  String? country;
  for (final p in parts.skip(1)) {
    if (p.length == 4 && script == null) {
      script = p;
    } else if ((p.length == 2 || p.length == 3) && country == null) {
      country = p;
    }
  }
  return Locale.fromSubtags(
      languageCode: language, scriptCode: script, countryCode: country);
}

/// Whether the UI is English. The single test for "show English-only content
/// as-is" (AI disclaimer note, raw server errors, legal-document notice) so
/// those surfaces can't disagree.
bool isEnglishUi(AppLocalizations l10n) =>
    l10n.localeName.split(RegExp('[_-]')).first == 'en';
