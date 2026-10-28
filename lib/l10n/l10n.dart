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
/// tag (`Locale.toLanguageTag()`: `es-419`, `zh`). Deliberately NOT
/// localized — a user who can't read the current language must still find
/// their own. Keep in sync with the `app_*.arb` files; the Android/iOS
/// declarations use [platformLocaleTag] (test-enforced in l10n_test.dart).
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

/// The tag a platform locale list (`locales_config.xml`,
/// `CFBundleLocalizations`) declares for an ARB locale. gen-l10n requires a
/// BASE file per language, so Traditional Chinese ships as the bare `zh`
/// ARB — but Android/iOS should still label it "Chinese (Traditional)".
/// Add `zh-Hans` as its own ARB (`app_zh_Hans.arb`, base stays Traditional)
/// if Simplified is ever shipped.
String platformLocaleTag(Locale locale) {
  const overrides = {'zh': 'zh-Hant'};
  final tag = locale.toLanguageTag();
  return overrides[tag] ?? tag;
}

/// The intl locale id that carries [locale]'s number/date symbols. intl's
/// `zh` is Simplified (周三), so the bare-`zh` Traditional ARB formats as
/// Taiwan (`zh_TW`, 週三); `es_419` exists as-is; plain languages use their
/// bare code (`fr`, not `fr_CA` — a UI locale is always a supported one,
/// never a raw device variant). Every intl call keyed on a UI locale must go
/// through here (or [intlLocaleOf]), never `l10n.localeName` directly.
String intlLocaleCode(Locale locale) {
  const overrides = {'zh': 'zh_TW'};
  final tag = locale.toString();
  if (overrides.containsKey(tag)) return overrides[tag]!;
  final country = locale.countryCode;
  return country == null
      ? locale.languageCode
      : '${locale.languageCode}_$country';
}

/// [intlLocaleCode] for the locale an [AppLocalizations] was built for.
String intlLocaleOf(AppLocalizations l10n) =>
    intlLocaleCode(localeFromLanguageTag(l10n.localeName));

/// Parses a BCP-47 / POSIX tag (`zh-Hant`, `es_419`, `fr`, `zh-Hant-TW`)
/// back into a [Locale]: a 4-letter subtag is the script, a 2-letter or
/// 3-digit one the region. Case is normalised to the canonical form
/// (`zh-hant-tw` → `zh_Hant_TW`); an empty tag yields `und` (which no
/// supported-locale check matches) instead of tripping Locale's assert.
/// Pure; used for the persisted language preference and `l10n.localeName`.
Locale localeFromLanguageTag(String tag) {
  final parts =
      tag.split(RegExp('[_-]')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return const Locale('und');
  final language = parts.first.toLowerCase();
  String? script;
  String? country;
  for (final p in parts.skip(1)) {
    if (p.length == 4 && script == null) {
      script = p[0].toUpperCase() + p.substring(1).toLowerCase();
    } else if ((p.length == 2 || p.length == 3) && country == null) {
      country = p.toUpperCase();
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
