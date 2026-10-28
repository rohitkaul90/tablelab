import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablelab/l10n/l10n.dart';
import 'package:tablelab/providers/locale_provider.dart';
import 'package:tablelab/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  const zhHant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  const es419 = Locale('es', '419');

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

  group('matchSupportedLocale — script and region variants', () {
    // The phase-3 set: one Chinese (Traditional) and two Spanish variants.
    const supported = [
      Locale('en'),
      Locale('es'),
      es419,
      Locale('fr'),
      Locale('ja'),
      Locale('ko'),
      zhHant,
    ];

    Locale resolve(Locale device) =>
        resolveLocale(null, [device], supported: supported);

    test('any Chinese device gets Traditional Chinese (the only zh shipped)', () {
      expect(resolve(const Locale('zh', 'TW')), zhHant);
      expect(
        resolve(const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK')),
        zhHant,
      );
      expect(
        resolve(const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')),
        zhHant,
      );
      expect(resolve(const Locale('zh')), zhHant);
    });

    test('a matching script wins once two scripts are shipped', () {
      const zhHans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      final both = [...supported, zhHans];
      expect(
        resolveLocale(
            null,
            const [
              Locale.fromSubtags(
                  languageCode: 'zh', scriptCode: 'Hans', countryCode: 'SG')
            ],
            supported: both),
        zhHans,
      );
      expect(
        resolveLocale(null, const [Locale('zh', 'TW')], supported: both),
        zhHant,
        reason: 'no script on the device → the first zh entry (Hant)',
      );
    });

    test('Spanish outside Spain is Latin American', () {
      for (final country in ['MX', 'AR', 'CO', 'CL', 'PE', 'US']) {
        expect(resolve(Locale('es', country)), es419, reason: 'es-$country');
      }
    });

    test('Spain and bare Spanish stay European Spanish', () {
      expect(resolve(const Locale('es', 'ES')), const Locale('es'));
      expect(resolve(const Locale('es')), const Locale('es'));
    });

    test('plain languages are unaffected by the variant rules', () {
      expect(resolve(const Locale('ja', 'JP')), const Locale('ja'));
      expect(resolve(const Locale('ko', 'KR')), const Locale('ko'));
      expect(resolve(const Locale('fr', 'CA')), const Locale('fr'));
      expect(resolve(const Locale('pt', 'BR')), const Locale('en'));
    });

    test('the device list order still decides between languages', () {
      expect(
        resolveLocale(null, const [Locale('pt'), Locale('ko'), Locale('ja')],
            supported: supported),
        const Locale('ko'),
      );
    });
  });

  group('localeFromLanguageTag', () {
    test('parses bare, script, region and full tags in either separator', () {
      expect(localeFromLanguageTag('fr'), const Locale('fr'));
      expect(localeFromLanguageTag('zh-Hant'), zhHant);
      expect(localeFromLanguageTag('zh_Hant'), zhHant);
      expect(localeFromLanguageTag('es-419'), es419);
      expect(localeFromLanguageTag('es_419'), es419);
      expect(
        localeFromLanguageTag('zh-Hant-TW'),
        const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
      );
    });

    test('round-trips Locale.toLanguageTag()', () {
      for (final l in [const Locale('en'), zhHant, es419, const Locale('fr', 'CA')]) {
        expect(localeFromLanguageTag(l.toLanguageTag()), l);
      }
    });
  });

  group('intlLocaleCode', () {
    test('maps the UI locale to an intl locale that has symbol data', () {
      expect(intlLocaleCode(const Locale('en')), 'en');
      expect(intlLocaleCode(const Locale('nl')), 'nl');
      expect(intlLocaleCode(const Locale('ja')), 'ja');
      expect(intlLocaleCode(zhHant), 'zh_TW');
      expect(intlLocaleCode(es419), 'es_419');
    });

    test('every phase-3 intl locale loads date symbols and formats', () async {
      final before = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = before);
      final d = DateTime(2026, 10, 28);
      for (final l in [const Locale('ja'), const Locale('ko'), zhHant, es419]) {
        await applyIntlLocale(l);
        expect(Intl.defaultLocale, intlLocaleCode(l));
        // Throws if the symbols were not loaded for Intl.defaultLocale.
        expect(DateFormat.yMMMd().format(d), isNotEmpty, reason: '$l');
        expect(NumberFormat('#,##0').format(1234), '1,234', reason: '$l');
      }
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
      // A tag this build does not ship is ignored, not crashed on.
      expect(LocaleNotifier(await prefsWith({'locale': 'zh-Hant-XX'})).state,
          isNull);
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

    test('a script/region locale persists as its language tag', () async {
      final prefs = await prefsWith({});
      final notifier = LocaleNotifier(prefs);
      final before = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = before);
      await notifier.set(zhHant);
      expect(prefs.getString('locale'), 'zh-Hant');
      // Reads back once the ARB ships; until then it is filtered to System.
      expect(
        LocaleNotifier(prefs).state,
        AppLocalizations.supportedLocales.contains(zhHant) ? zhHant : isNull,
      );
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
