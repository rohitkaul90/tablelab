// parseSprFilter tests (bulk-density prep): the TLSOLVE_SPRS include-filter
// must parse leniently (trim/case/empty) but fail FAST on bucket names the
// selected scenario doesn't have — 3bp has committed/shallow/medium and no
// deep, so a filter valid for an srp scenario can be a hard error for 3bp.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/solver/spot_sched.dart';

void main() {
  const srpBuckets = ['shallow', 'medium', 'deep'];
  const threeBetBuckets = ['committed', 'shallow', 'medium'];

  group('parseSprFilter', () {
    test('unset / empty / whitespace → null (no filter)', () {
      expect(parseSprFilter(null, srpBuckets), isNull);
      expect(parseSprFilter('', srpBuckets), isNull);
      expect(parseSprFilter('   ', srpBuckets), isNull);
      expect(parseSprFilter(' , ,', srpBuckets), isNull);
    });

    test('single bucket', () {
      expect(parseSprFilter('deep', srpBuckets), {'deep'});
    });

    test('comma list with spaces and mixed case', () {
      expect(parseSprFilter(' Shallow , MEDIUM ', srpBuckets),
          {'shallow', 'medium'});
    });

    test('unknown bucket throws with the valid set named', () {
      expect(
        () => parseSprFilter('deeep', srpBuckets),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('shallow'))),
      );
    });

    test('srp-only bucket against the 3bp bucket set throws', () {
      // The cross-scenario footgun: TLSOLVE_SPRS=deep is valid for the srp
      // scenarios but 3bp has no deep regime — it must fail, not solve zero.
      expect(() => parseSprFilter('deep', threeBetBuckets),
          throwsA(isA<StateError>()));
      expect(parseSprFilter('committed', threeBetBuckets), {'committed'});
    });
  });
}
