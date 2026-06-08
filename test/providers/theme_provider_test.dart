import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablelab/providers/theme_provider.dart';

void main() {
  // SharedPreferences mock channel needs the test binding initialised.
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  group('ThemeModeNotifier', () {
    test('defaults to system when nothing is persisted', () async {
      final notifier = ThemeModeNotifier(await prefsWith({}));
      expect(notifier.state, ThemeMode.system);
    });

    test('reads a persisted light preference on construction', () async {
      final notifier =
          ThemeModeNotifier(await prefsWith({'theme_mode': 'light'}));
      expect(notifier.state, ThemeMode.light);
    });

    test('reads a persisted dark preference on construction', () async {
      final notifier =
          ThemeModeNotifier(await prefsWith({'theme_mode': 'dark'}));
      expect(notifier.state, ThemeMode.dark);
    });

    test('an unrecognised stored value falls back to system', () async {
      final notifier =
          ThemeModeNotifier(await prefsWith({'theme_mode': 'rainbow'}));
      expect(notifier.state, ThemeMode.system);
    });

    test('set() updates state and persists across a fresh notifier', () async {
      final prefs = await prefsWith({});
      final notifier = ThemeModeNotifier(prefs);

      await notifier.set(ThemeMode.dark);

      expect(notifier.state, ThemeMode.dark);
      expect(prefs.getString('theme_mode'), 'dark');
      // A notifier rebuilt from the same prefs (e.g. next app launch) restores it.
      expect(ThemeModeNotifier(prefs).state, ThemeMode.dark);
    });

    test('setting the current mode is a no-op (no redundant write)', () async {
      final prefs = await prefsWith({});
      final notifier = ThemeModeNotifier(prefs);
      await notifier.set(ThemeMode.system); // already system
      expect(prefs.getString('theme_mode'), isNull);
    });
  });

  group('themeModeProvider', () {
    test('exposes the persisted value through the provider', () async {
      final prefs = await prefsWith({'theme_mode': 'light'});
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.light);

      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(prefs.getString('theme_mode'), 'dark');
    });
  });
}
