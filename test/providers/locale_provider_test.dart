import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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

  const zh = Locale('zh');
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
    // The phase-3 set as gen-l10n allows it: Traditional Chinese is the bare
    // `zh` base ARB (a script variant needs a base file), Spanish ships twice.
    // Sorted like AppLocalizations.supportedLocales (gen-l10n sorts).
    const supported = [
      Locale('en'),
      Locale('es'),
      es419,
      Locale('fr'),
      Locale('ja'),
      Locale('ko'),
      zh,
    ];

    Locale resolve(Locale device) =>
        resolveLocale(null, [device], supported: supported);

    test('any Chinese device gets the one shipped Chinese (Traditional)', () {
      expect(resolve(const Locale('zh', 'TW')), zh);
      expect(
        resolve(const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK')),
        zh,
      );
      expect(
        resolve(const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')),
        zh,
      );
      expect(resolve(zh), zh);
    });

    test('with a second script shipped, script then region table decide', () {
      // Hypothetical future: base `zh` = Simplified, `zh_Hant` = Traditional.
      final both = [...supported, zhHant];
      Locale r(Locale d) => resolveLocale(null, [d], supported: both);
      expect(
        r(const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK')),
        zhHant,
        reason: 'script match',
      );
      expect(
        r(const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: 'SG')),
        zh,
        reason: 'no Hans entry → base',
      );
      expect(r(const Locale('zh', 'TW')), zhHant, reason: 'TW → Hant table');
      expect(r(const Locale('zh', 'MO')), zhHant, reason: 'MO → Hant table');
      expect(r(const Locale('zh', 'CN')), zh, reason: 'CN not in table → base');
      expect(r(zh), zh, reason: 'no region → base');
    });

    test('Spanish outside Spain is Latin American', () {
      for (final country in ['MX', 'AR', 'CO', 'CL', 'PE', 'US']) {
        expect(resolve(Locale('es', country)), es419, reason: 'es-$country');
      }
    });

    test('Spain and bare Spanish stay European Spanish', () {
      expect(resolve(const Locale('es', 'ES')), const Locale('es'));
      expect(resolve(const Locale('es', 'EA')), const Locale('es'));
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

    test('normalises case and tolerates an empty tag', () {
      expect(localeFromLanguageTag('ZH-hant-tw'),
          localeFromLanguageTag('zh-Hant-TW'));
      expect(localeFromLanguageTag('fr-ca'), const Locale('fr', 'CA'));
      expect(localeFromLanguageTag(''), const Locale('und'));
      expect(localeFromLanguageTag('-'), const Locale('und'));
      expect(AppLocalizations.supportedLocales.contains(const Locale('und')),
          isFalse);
    });

    test('round-trips Locale.toLanguageTag()', () {
      for (final l in [const Locale('en'), zhHant, es419, const Locale('fr', 'CA')]) {
        expect(localeFromLanguageTag(l.toLanguageTag()), l);
      }
    });
  });

  group('intlLocaleCode / platformLocaleTag', () {
    test('maps the UI locale to an intl locale that has symbol data',
        () async {
      await initializeDateFormatting();
      expect(intlLocaleCode(const Locale('en')), 'en');
      expect(intlLocaleCode(const Locale('nl')), 'nl');
      expect(intlLocaleCode(const Locale('ja')), 'ja');
      expect(intlLocaleCode(zh), 'zh_TW');
      expect(intlLocaleCode(es419), 'es_419');
      for (final l in [const Locale('ja'), const Locale('ko'), zh, es419]) {
        expect(DateFormat.localeExists(intlLocaleCode(l)), isTrue,
            reason: '$l');
      }
    });

    test('the bare zh ARB is declared as zh-Hant on the platforms', () {
      expect(platformLocaleTag(zh), 'zh-Hant');
      expect(platformLocaleTag(es419), 'es-419');
      expect(platformLocaleTag(const Locale('nl')), 'nl');
    });

    test('applyIntlLocale formats with the mapped symbols, not the bare code',
        () async {
      final before = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = before);
      final wed = DateTime(2026, 10, 28); // a Wednesday
      // Traditional-script weekday (週三); intl's bare `zh` would give 周三.
      await applyIntlLocale(zh);
      expect(Intl.defaultLocale, 'zh_TW');
      expect(DateFormat.E().format(wed), '週三');
      await applyIntlLocale(const Locale('ja'));
      expect(DateFormat.E().format(wed), '水');
      await applyIntlLocale(const Locale('ko'));
      expect(DateFormat.E().format(wed), '수');
      await applyIntlLocale(es419);
      expect(Intl.defaultLocale, 'es_419');
      expect(DateFormat.E().format(wed), 'mié');
      expect(NumberFormat('#,##0').format(1234), '1,234');
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

    test('"system", unknown and empty stored values all mean follow the device',
        () async {
      expect(LocaleNotifier(await prefsWith({'locale': 'system'})).state, isNull);
      expect(LocaleNotifier(await prefsWith({'locale': 'xx'})).state, isNull);
      expect(LocaleNotifier(await prefsWith({'locale': ''})).state, isNull);
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

    test('a region locale persists as its language tag', () async {
      final prefs = await prefsWith({});
      final notifier = LocaleNotifier(prefs);
      final before = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = before);
      await notifier.set(es419);
      expect(prefs.getString('locale'), 'es-419');
      expect(Intl.defaultLocale, 'es_419');
      // Reads back once the ARB ships; until then it is filtered to System.
      expect(
        LocaleNotifier(prefs).state,
        AppLocalizations.supportedLocales.contains(es419) ? es419 : isNull,
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
