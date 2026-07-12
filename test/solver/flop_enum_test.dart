// Suit-isomorphic flop enumeration tests (full-density plan WS2). The 1,755
// count is a hard mathematical fact (1,430 unpaired + 312 paired + 13 trips) —
// any other number means the canonicalization is broken.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';

import '../../tool/solver/flop_enum.dart';

List<int> _f(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

void main() {
  group('allIsoFlops', () {
    late final List<String> flops = allIsoFlops();

    test('yields exactly 1,755 canonical classes', () {
      expect(flops.length, 1755);
      expect(flops.toSet().length, 1755); // no duplicates
    });

    test('every flop is 3 valid, distinct cards', () {
      for (final f in flops) {
        final cards = _f(f);
        expect(cards.length, 3, reason: f);
        expect(cards.toSet().length, 3, reason: f);
        expect(cards.every((c) => c >= 0 && c < 52), isTrue, reason: f);
      }
    });

    test('every flop is its own canonical form (fixed point)', () {
      for (final f in flops.take(200)) {
        expect(canonicalFlop(_f(f)), f);
      }
    });
  });

  group('canonicalFlop', () {
    test('isomorphic flops map to the same representative', () {
      // Same rank pattern, suits relabeled h↔s, d↔c.
      expect(canonicalFlop(_f('Ks 9h 4c')), canonicalFlop(_f('Kh 9s 4d')));
      // Monotone in each of the four suits — all one class.
      final mono = {
        for (final s in ['c', 'd', 'h', 's'])
          canonicalFlop(_f('K$s Q$s J$s')),
      };
      expect(mono.length, 1);
    });

    test('non-isomorphic flops stay distinct', () {
      // Two-tone vs rainbow of the same ranks.
      expect(canonicalFlop(_f('Kh 9h 4c')),
          isNot(canonicalFlop(_f('Kh 9s 4c'))));
      // Paired vs unpaired.
      expect(canonicalFlop(_f('Ks Kh 4c')),
          isNot(canonicalFlop(_f('Ks Qh 4c'))));
    });

    test('card input order does not matter', () {
      expect(canonicalFlop(_f('4c 9h Ks')), canonicalFlop(_f('Ks 9h 4c')));
    });
  });

  group('strideSlice', () {
    late final List<String> all = allIsoFlops();

    test('5 × 351 slices at offsets 0..4 partition all 1,755 exactly', () {
      // The committed bulk-campaign slice files (tool/solver/flops/) rely on
      // this: when count divides the list length, the stride is uniform and
      // phase offsets 0..K-1 are pairwise disjoint and union to the whole.
      final slices = [for (var k = 0; k < 5; k++) strideSlice(all, 351, k)];
      final union = <String>{};
      var total = 0;
      for (final s in slices) {
        expect(s.length, 351);
        total += s.length;
        union.addAll(s);
      }
      expect(total, 1755);
      expect(union.length, 1755); // pairwise disjoint AND covering
      expect(union, all.toSet());
    });

    test('slices are deterministic and stride-spread (not a prefix)', () {
      final s0 = strideSlice(all, 351, 0);
      expect(strideSlice(all, 351, 0), s0); // deterministic
      expect(s0.first, all.first);
      // Stride 5: the slice spans the whole sorted list, not its head.
      expect(s0[1], all[5]);
      expect(s0.last, all[1750]);
    });

    test('modSlice partitions for any m: 4 deals cover 1,755 exactly', () {
      // 1,755 isn't divisible by 4, so the stride partition can't make a
      // 4-way split — the round-robin deal can (sizes 439/439/439/438).
      final slices = [for (var k = 0; k < 4; k++) modSlice(all, k, 4)];
      expect(slices.map((s) => s.length), [439, 439, 439, 438]);
      final union = <String>{};
      for (final s in slices) {
        union.addAll(s);
      }
      expect(union.length, 1755); // pairwise disjoint AND covering
      expect(union, all.toSet());
    });

    test('the COMMITTED mod-4 slice files match modSlice byte-for-byte', () {
      // Same artifact-lock rationale as the 5-way stride files below: the
      // 4-box fleet (stages 2-5) consumes the committed files, not the
      // function — a stale file silently breaks slice disjointness.
      for (var k = 0; k < 4; k++) {
        final f = File('tool/solver/flops/slice4_mod$k.txt');
        expect(f.existsSync(), isTrue, reason: '${f.path} missing');
        final lines = f
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .toList();
        expect(lines, modSlice(all, k, 4),
            reason: '${f.path} is stale — regenerate: '
                'dart run tool/solver/flop_enum.dart mod 4 $k ${f.path}');
      }
    });

    test('the COMMITTED slice files match strideSlice byte-for-byte', () {
      // The boxes consume the committed tool/solver/flops/*.txt artifacts (via
      // git archive), NOT the function — a stale/hand-edited/regenerated-
      // under-a-changed-canonicalization file would silently break the
      // disjoint-partition property two concurrently-running boxes rely on
      // (overlaps re-solve paid spots; dropped flops become coverage holes).
      final union = <String>{};
      for (var k = 0; k < 5; k++) {
        final f = File('tool/solver/flops/slice351_off$k.txt');
        expect(f.existsSync(), isTrue, reason: '${f.path} missing');
        final lines = f
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .toList();
        expect(lines, strideSlice(all, 351, k),
            reason: '${f.path} is stale — regenerate: '
                'dart run tool/solver/flop_enum.dart 351 ${f.path} $k');
        union.addAll(lines);
      }
      expect(union.length, 1755);
    });
  });
}
