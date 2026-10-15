import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablelab/providers/locale_provider.dart';
import 'package:tablelab/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  group('resolveLocale', () {
    const supported = [Locale('en'), Locale('es'), Locale('fr')];

    test('an explicit preference wins over the device', () {
      expect(
        resolveLocale(const Locale('es'), const [Locale('fr')], supported: supported),
        const Locale('es'),
      );
    });

    test('system mode picks the first supported device language', () {
      expect(
        resolveLocale(null, const [Locale('de'), Locale('fr', 'CA')], supported: supported),
        const Locale('fr'),
      );
    });

    test('a region variant maps to its language', () {
      expect(
        resolveLocale(null, const [Locale('es', 'MX')], supported: supported),
        const Locale('es'),
      );
    });

    test('an unsupported device language falls back to English', () {
      expect(
        resolveLocale(null, const [Locale('de'), Locale('pl')], supported: supported),
        const Locale('en'),
      );
    });

    test('no device locales at all falls back to English', () {
      expect(resolveLocale(null, const [], supported: supported), const Locale('en'));
    });
  });

  group('LocaleNotifier', () {
    test('defaults to system (null) when nothing is persisted', () async {
      expect(LocaleNotifier(await prefsWith({})).state, isNull);
    });

    test('reads a persisted language on construction', () async {
      expect(
        LocaleNotifier(await prefsWith({'locale': 'fr'})).state,
        const Locale('fr'),
      );
    });

    test('"system" and unknown stored values both mean follow the device',
        () async {
      expect(LocaleNotifier(await prefsWith({'locale': 'system'})).state, isNull);
      expect(LocaleNotifier(await prefsWith({'locale': 'xx'})).state, isNull);
    });

    test('set() persists, applies the intl default and restores on relaunch',
        () async {
      final prefs = await prefsWith({});
      final notifier = LocaleNotifier(prefs);
      final before = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = before);

      await notifier.set(const Locale('es'));

      expect(notifier.state, const Locale('es'));
      expect(prefs.getString('locale'), 'es');
      expect(Intl.defaultLocale, 'es');
      expect(LocaleNotifier(prefs).state, const Locale('es'));

      await notifier.set(null);
      expect(prefs.getString('locale'), 'system');
      expect(LocaleNotifier(prefs).state, isNull);
    });

    test('setting the current value is a no-op (no redundant write)', () async {
      final prefs = await prefsWith({});
      await LocaleNotifier(prefs).set(null);
      expect(prefs.getString('locale'), isNull);
    });
  });

  group('providers', () {
    test('resolvedLocaleProvider follows the persisted preference', () async {
      final prefs = await prefsWith({'locale': 'it'});
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);
      final before = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = before);

      expect(container.read(resolvedLocaleProvider), const Locale('it'));

      await container.read(localeProvider.notifier).set(const Locale('nl'));
      expect(container.read(resolvedLocaleProvider), const Locale('nl'));
    });
  });
}
