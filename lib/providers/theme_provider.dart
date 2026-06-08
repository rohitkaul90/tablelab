import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the [SharedPreferences] instance. Overridden in `main()` after the
/// instance has loaded, so the rest of the app can read it synchronously.
/// Throwing here guarantees we never forget the override.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

const _themeModeKey = 'theme_mode';

/// App theme mode (System / Light / Dark), persisted locally so it applies at
/// launch — before Supabase auth resolves — avoiding a dark→light flash on
/// cold start. Local (not profile) storage is deliberate for this reason.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static ThemeMode _read(SharedPreferences prefs) {
    switch (prefs.getString(_themeModeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _prefs.setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(sharedPreferencesProvider));
});
