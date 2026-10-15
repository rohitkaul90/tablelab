import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/arb_check.dart';

void main() {
  group('placeholdersOf', () {
    test('simple placeholders', () {
      expect(placeholdersOf('Hello {name}, {count} new'), {'name', 'count'});
    });

    test('ICU plural argument counts once, branch bodies are not placeholders',
        () {
      expect(
        placeholdersOf('{count, plural, one{{count} session} other{{count} sessions}}'),
        {'count'},
      );
    });

    test('select branch literals are not placeholders', () {
      expect(
        placeholdersOf('{type, select, cash{Cash game} tournament{Tournament} other{Game}}'),
        {'type'},
      );
    });

    test('literal braces without an identifier are ignored', () {
      expect(placeholdersOf('a { } b {1x}'), isEmpty);
    });
  });

  group('missingOtherBranch', () {
    test('flags plural without other', () {
      expect(missingOtherBranch('{n, plural, one{x}}'), isTrue);
    });
    test('accepts plural with other', () {
      expect(missingOtherBranch('{n, plural, one{x} other{y}}'), isFalse);
    });
    test('ignores plain messages', () {
      expect(missingOtherBranch('other things {n}'), isFalse);
    });
  });

  group('validateMessage', () {
    test('placeholder mismatch is reported', () {
      final p = validateMessage(
          key: 'k', english: 'Hi {name}', candidate: 'Hola', locale: 'es');
      expect(p.single, contains('placeholders differ'));
    });
    test('clean translation passes', () {
      expect(
        validateMessage(
            key: 'k', english: 'Hi {name}', candidate: 'Hola {name}', locale: 'es'),
        isEmpty,
      );
    });
  });

  group('checkArb', () {
    final template = <String, dynamic>{
      '@@locale': 'en',
      'greeting': 'Hello {name}',
      '@greeting': {'description': 'Shown on the home screen'},
      'close': 'Close',
      '@close': {'description': 'Dialog dismiss button'},
    };
    Map<String, Map<String, String>> freshState(
        Map<String, dynamic> es) =>
        {
          'es': {
            for (final k in messageKeys(template)) k: sourceHash(template[k] as String),
          },
        };

    test('passes a complete, fresh target', () {
      final es = <String, dynamic>{
        '@@locale': 'es',
        'greeting': 'Hola {name}',
        'close': 'Cerrar',
      };
      expect(
        checkArb(template: template, targets: {'es': es}, state: freshState(es)),
        isEmpty,
      );
    });

    test('reports missing, extra, stale and mismatched keys', () {
      final es = <String, dynamic>{
        '@@locale': 'es',
        'greeting': 'Hola',
        'obsolete': 'x',
      };
      final problems = checkArb(
        template: template,
        targets: {'es': es},
        state: {
          'es': {'greeting': 'not-the-hash'},
        },
      );
      expect(problems.join('\n'), contains('close: missing'));
      expect(problems.join('\n'), contains('obsolete: not in app_en.arb'));
      expect(problems.join('\n'), contains('greeting: placeholders differ'));
      expect(problems.join('\n'), contains('greeting: translation is stale'));
    });

    test('a hand-added translation with no recorded hash is reported as such',
        () {
      final es = <String, dynamic>{
        '@@locale': 'es',
        'greeting': 'Hola {name}',
        'close': 'Cerrar',
      };
      final problems = checkArb(template: template, targets: {'es': es}, state: {});
      expect(problems, hasLength(2));
      expect(problems.join('\n'), contains('no entry in translation_state.json'));
      expect(problems.join('\n'), isNot(contains('stale')));
    });

    test('short English messages need a description', () {
      final bare = <String, dynamic>{'@@locale': 'en', 'call': 'Call'};
      final problems = checkArb(template: bare, targets: {}, state: {});
      expect(problems.single, contains('needs an @call.description'));
    });

    test('wrong @@locale is reported', () {
      final es = <String, dynamic>{'@@locale': 'fr', 'greeting': 'Hola {name}', 'close': 'Cerrar'};
      final problems = checkArb(
          template: template, targets: {'es': es}, state: freshState(es));
      expect(problems.single, contains('@@locale must be "es"'));
    });
  });
}
