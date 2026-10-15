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
  static Locale? read(SharedPreferences prefs) {
    final stored = prefs.getString(_localeKey);
    if (stored == null || stored == _systemValue) return null;
    final locale = Locale(stored);
    return AppLocalizations.supportedLocales.contains(locale) ? locale : null;
  }

  /// Persists the choice and switches intl's number/date symbols BEFORE the
  /// state change so the first rebuild already formats in the new locale.
  Future<void> set(Locale? locale) async {
    if (locale == state) return;
    await applyIntlLocale(resolveLocale(locale, _deviceLocales()));
    state = locale;
    await _prefs.setString(_localeKey, locale?.languageCode ?? _systemValue);
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
/// of `deviceLocales` whose language code is supported (`fr-CA` → `fr`);
/// otherwise `en`.
Locale resolveLocale(
  Locale? preference,
  List<Locale> deviceLocales, {
  List<Locale> supported = AppLocalizations.supportedLocales,
}) {
  if (preference != null) return preference;
  for (final device in deviceLocales) {
    for (final s in supported) {
      if (s.languageCode == device.languageCode) return s;
    }
  }
  return const Locale('en');
}

/// Loads intl's date symbols for [locale] and makes it the default for every
/// bare `NumberFormat`/`DateFormat` in the app (helpers.dart formats through
/// `Intl.defaultLocale`). Called at startup and on every language change.
Future<void> applyIntlLocale(Locale locale) async {
  final code = locale.languageCode;
  await initializeDateFormatting(code);
  Intl.defaultLocale = code;
}
