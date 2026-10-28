import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import 'theme_provider.dart' show sharedPreferencesProvider;

const _localeKey = 'locale';
const _systemValue = 'system';

/// The user's explicit language choice, or `null` for "System" (follow the
/// device). Persisted locally — like the theme — so it applies on cold start
/// BEFORE Supabase auth resolves (the login screen and onboarding must already
/// be in the right language; a profile round-trip would flash English).
class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier(this._prefs) : super(read(_prefs));

  final SharedPreferences _prefs;

  /// The stored preference (`null` = system). Public so `main()` can resolve
  /// the startup locale before the provider container exists.
  ///
  /// Stored as a BCP-47 language tag (`zh-Hant`, `es-419`, `fr`) — the bare
  /// language codes written by builds before the script/region locales still
  /// parse to the same `Locale`.
  static Locale? read(SharedPreferences prefs) {
    final stored = prefs.getString(_localeKey);
    if (stored == null || stored == _systemValue) return null;
    final locale = localeFromLanguageTag(stored);
    return AppLocalizations.supportedLocales.contains(locale) ? locale : null;
  }

  /// Persists the choice and switches intl's number/date symbols BEFORE the
  /// state change so the first rebuild already formats in the new locale.
  Future<void> set(Locale? locale) async {
    if (locale == state) return;
    await applyIntlLocale(resolveLocale(locale, _deviceLocales()));
    state = locale;
    await _prefs.setString(_localeKey, locale?.toLanguageTag() ?? _systemValue);
  }
}

final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier(ref.watch(sharedPreferencesProvider));
});

/// The locale the UI actually renders in: the explicit preference, else the
/// first device locale whose language is supported, else English.
/// Invalidate on `didChangeLocales` so "System" mode tracks the device.
final resolvedLocaleProvider = Provider<Locale>((ref) {
  return resolveLocale(ref.watch(localeProvider), _deviceLocales());
});

List<Locale> _deviceLocales() =>
    WidgetsBinding.instance.platformDispatcher.locales;

/// Pure resolution rule (unit-tested): `preference` wins; otherwise the first
/// of `deviceLocales` whose language is supported, picking the best variant
/// of that language via [matchSupportedLocale]; otherwise `en`.
Locale resolveLocale(
  Locale? preference,
  List<Locale> deviceLocales, {
  List<Locale> supported = AppLocalizations.supportedLocales,
}) {
  if (preference != null) return preference;
  for (final device in deviceLocales) {
    final match = matchSupportedLocale(device, supported);
    if (match != null) return match;
  }
  return const Locale('en');
}

/// The best supported variant of [device]'s language, or `null` when the
/// language isn't shipped at all. Among the supported locales that share the
/// language code:
///  1. same script wins (`zh-Hant-HK` → `zh_Hant`);
///  2. then same country (`es-ES` → `es`, were `es_ES` ever shipped);
///  3. Spanish outside Spain is Latin American (`es-MX`/`es-US`/`es-AR` →
///     `es_419`; bare `es` and `es-ES` → `es`);
///  4. otherwise the base locale (no script/country), else the first one —
///     so a lone `zh_Hant` serves every `zh` device, Simplified included
///     (readable, and far better than English; add `zh_Hans` when installs
///     justify it).
Locale? matchSupportedLocale(Locale device, List<Locale> supported) {
  final sameLanguage =
      supported.where((s) => s.languageCode == device.languageCode).toList();
  if (sameLanguage.isEmpty) return null;
  if (sameLanguage.length == 1) return sameLanguage.first;

  final script = device.scriptCode;
  if (script != null) {
    for (final s in sameLanguage) {
      if (s.scriptCode == script) return s;
    }
  }
  final country = device.countryCode;
  if (country != null) {
    for (final s in sameLanguage) {
      if (s.countryCode == country) return s;
    }
    if (device.languageCode == 'es' && country != 'ES') {
      for (final s in sameLanguage) {
        if (s.countryCode == kLatinAmericaRegion) return s;
      }
    }
  }
  for (final s in sameLanguage) {
    if (s.scriptCode == null && s.countryCode == null) return s;
  }
  return sameLanguage.first;
}

/// UN M.49 region code for Latin America & the Caribbean — the `es_419`
/// locale's "country".
const kLatinAmericaRegion = '419';

/// Loads intl's date symbols for [locale] and makes it the default for every
/// bare `NumberFormat`/`DateFormat` in the app (helpers.dart formats through
/// `Intl.defaultLocale`). Called at startup and on every language change.
Future<void> applyIntlLocale(Locale locale) async {
  final code = intlLocaleCode(locale);
  await initializeDateFormatting(code);
  Intl.defaultLocale = code;
}

/// The intl locale id that carries [locale]'s number/date symbols. intl ships
/// no `zh_Hant` data, so Traditional Chinese formats as Taiwan (`zh_TW`);
/// `es_419` exists as-is; plain languages use their bare code (`fr`, not
/// `fr_CA` — the UI locale is already a supported one, never a device
/// variant).
String intlLocaleCode(Locale locale) {
  const overrides = {'zh_Hant': 'zh_TW'};
  final tag = locale.toString();
  if (overrides.containsKey(tag)) return overrides[tag]!;
  final country = locale.countryCode;
  return country == null
      ? locale.languageCode
      : '${locale.languageCode}_$country';
}
