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

/// Region → variant fallbacks for languages shipped in more than one
/// variant, consulted when the device locale has no script and no
/// exact-country match. `'*'` is the wildcard region. Each language PR that
/// adds a variant adds one entry here instead of a resolver special case.
///
/// - `es`: Spain (and its EA/IC territories) stays `es`; every other region
///   (MX, AR, CO, US, …) is Latin American Spanish.
/// - `zh`: only meaningful once a second script ships alongside the base
///   `zh` ARB (today = Traditional, see [platformLocaleTag]): TW/HK/MO would
///   read the Traditional variant, the rest the base.
const Map<String, Map<String, Locale>> kRegionalVariants = {
  'es': {
    '*': Locale('es', '419'),
    'ES': Locale('es'),
    'EA': Locale('es'),
    'IC': Locale('es'),
  },
  'zh': {
    'TW': Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    'HK': Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    'MO': Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  },
};

/// The best supported variant of [device]'s language, or `null` when the
/// language isn't shipped at all. Among the supported locales that share the
/// language code:
///  1. a single shipped variant serves every device variant (so the bare
///     `zh` Traditional ARB serves zh-TW, zh-Hant-HK AND zh-Hans-CN —
///     readable, and far better than English);
///  2. same script wins (`zh-Hant-HK` → `zh_Hant`);
///  3. then same country (`es-ES` → `es_ES`, were it ever shipped);
///  4. then the [kRegionalVariants] table (`es-MX` → `es_419`);
///  5. otherwise the base locale (no script/country), else the first one.
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
  }
  // The region table only applies to a device locale that HAS a region: a
  // bare `es` is the base language, not the wildcard variant.
  final table = country == null ? null : kRegionalVariants[device.languageCode];
  if (table != null) {
    final variant = table[country] ?? table['*'];
    if (variant != null && sameLanguage.contains(variant)) return variant;
  }
  for (final s in sameLanguage) {
    if (s.scriptCode == null && s.countryCode == null) return s;
  }
  return sameLanguage.first;
}

/// Loads intl's date symbols for [locale] and makes it the default for every
/// bare `NumberFormat`/`DateFormat` in the app (helpers.dart formats through
/// `Intl.defaultLocale`). Called at startup and on every language change.
/// The locale → intl id mapping lives in [intlLocaleCode] (l10n.dart) so the
/// explicit-locale DateFormat sites use the same one.
Future<void> applyIntlLocale(Locale locale) async {
  final code = intlLocaleCode(locale);
  await initializeDateFormatting(code);
  Intl.defaultLocale = code;
}
