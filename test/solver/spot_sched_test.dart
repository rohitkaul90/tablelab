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

  group('spotFootprint deep claim', () {
    test('deepClaimGb overrides ONLY the deep class solve claim', () {
      final tuned = spotFootprint(15, dumpFmt: 'bin', deepClaimGb: 50);
      expect(tuned.solveGb, 50);
      expect(tuned.parseGb, 3); // parse claim unaffected (streaming default)
      // Non-deep classes ignore the override entirely.
      expect(spotFootprint(6, dumpFmt: 'bin', deepClaimGb: 50).solveGb, 36);
      expect(spotFootprint(3, dumpFmt: 'bin', deepClaimGb: 50).solveGb, 16);
    });

    test('default stays 100 with no override (env unset in tests)', () {
      expect(spotFootprint(15, dumpFmt: 'bin').solveGb, 100);
    });

    test('parse claims key off the real tabulate path', () {
      // Streaming (bin default): raw bytes + O(depth) — small claims. A
      // pending detached tabulate over-claiming the eager footprint would
      // starve solve admissions (the throughput the decoupling exists to
      // recover).
      expect(spotFootprint(15, dumpFmt: 'bin').parseGb, 3);
      expect(spotFootprint(6, dumpFmt: 'bin').parseGb, 1.5);
      // Eager TLSD rollback: typed tree at ~2-3× raw bytes.
      expect(spotFootprint(15, dumpFmt: 'bin', eagerTabulate: true).parseGb, 8);
      expect(spotFootprint(6, dumpFmt: 'bin', eagerTabulate: true).parseGb, 4);
      // JSON dumps always pay the giant jsonDecode heap, whatever the flag.
      expect(spotFootprint(15, dumpFmt: 'json').parseGb, 160);
      expect(spotFootprint(15, dumpFmt: 'both', eagerTabulate: false).parseGb,
          160);
    });
  });
}
