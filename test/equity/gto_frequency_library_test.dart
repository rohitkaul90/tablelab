import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/decision_context.dart' show HandClass;
import 'package:tablelab/equity/gto_frequency_library.dart';

/// A small in-memory library: one group (srp_late_v_bb / flop / ip / facing_check
/// / marginalMade) with cells spanning textures + SPR buckets, plus a thin cell.
GtoFrequencyLibrary _lib() => GtoFrequencyLibrary.fromJson({
      'version': 1,
      'meta': {'streets': 'flop'},
      'scenarios': {
        'srp_late_v_bb': {
          'range_ip': 'AA',
          'range_oop': 'KK',
          'rep_flops': {},
          'cells': [
            _cell('rainbow|unpaired|ace|disconnected', 'shallow',
                {'check': 0.40, 'bet_small': 0.60}, 100),
            _cell('rainbow|unpaired|ace|disconnected', 'medium',
                {'check': 0.50, 'bet_small': 0.50}, 80),
            _cell('rainbow|unpaired|broadway|disconnected', 'shallow',
                {'check': 0.55, 'bet_small': 0.45}, 60),
            _cell('monotone|unpaired|low|disconnected', 'shallow',
                {'check': 0.90, 'bet_small': 0.10}, 3), // thin
          ],
        },
      },
    });

Map<String, dynamic> _cell(
        String tex, String spr, Map<String, double> freqs, double mass) =>
    {
      'texture': tex,
      'spr_bucket': spr,
      'street': 'flop',
      'position': 'ip',
      'facing': 'facing_check',
      'hand_class': 'marginalMade',
      'freqs': freqs,
      'reach_weight': mass,
    };

List<int> _b(String s) => boardInts(s.split(' '));

GtoFrequencyResult? _q(GtoFrequencyLibrary lib, String board, String spr,
        {double minMass = 8.0, HandClass hc = HandClass.marginalMade}) =>
    lib.lookup(
      scenario: 'srp_late_v_bb',
      board: _b(board),
      sprBucket: spr,
      street: 'flop',
      position: 'ip',
      facing: 'facing_check',
      handClass: hc,
      minMass: minMass,
    );

void main() {
  group('GtoFrequencyLibrary.lookup', () {
    final lib = _lib();

    test('exact texture + SPR hit', () {
      final r = _q(lib, 'As Kd 7h', 'shallow')!; // rainbow|unpaired|ace|disconnected
      expect(r.freqs['check'], closeTo(0.40, 1e-9));
      expect(r.textureFallback, 0);
      expect(r.sprExact, isTrue);
      expect(r.isInterpolated, isFalse);
      expect(r.topAction, 'bet_small');
    });

    test('SPR is exact-only: an unsolved bucket misses (no cross-regime borrow)', () {
      // spr 'deep' is absent from the library (deep cash deferred) → no FACT,
      // rather than silently borrowing the medium-SPR mix.
      expect(_q(lib, 'As Kd 7h', 'deep'), isNull);
      expect(_q(lib, 'As Kd 7h', 'committed'), isNull);
    });

    test('texture fallback: drop connectedness', () {
      // Ah Qc Td = rainbow|unpaired|ace|CONNECTED (absent). Drops connectedness
      // → matches the disconnected ace cells; exact SPR (shallow) wins.
      final r = _q(lib, 'Ah Qc Td', 'shallow')!;
      expect(r.textureFallback, 1);
      expect(r.sprExact, isTrue);
      expect(r.freqs['check'], closeTo(0.40, 1e-9)); // shallow ace cell
    });

    test('drop-high-card merge requires raising the texture-fallback cap', () {
      // 9s 5h 2c = rainbow|unpaired|MIDDLING|disconnected (absent until high-card
      // is dropped, level 2). Default cap (1) misses; cap 3 merges the ace
      // (mass100, check .40) + broadway (mass60, check .55) cells by mass.
      expect(_q(lib, '9s 5h 2c', 'shallow'), isNull); // default cap 1 → miss
      final r = lib.lookup(
        scenario: 'srp_late_v_bb',
        board: _b('9s 5h 2c'),
        sprBucket: 'shallow',
        street: 'flop',
        position: 'ip',
        facing: 'facing_check',
        handClass: HandClass.marginalMade,
        maxTextureFallback: 3,
      )!;
      expect(r.textureFallback, 2);
      expect(r.reachWeight, closeTo(160, 1e-9));
      expect(r.freqs['check'], closeTo((0.40 * 100 + 0.55 * 60) / 160, 1e-6));
    });

    test('thin cell is suppressed below minMass → miss', () {
      // monotone|unpaired|low|disconnected has only the mass-3 cell at every
      // relaxation level → below the default floor → null.
      expect(_q(lib, '7s 5s 2s', 'shallow'), isNull);
      // …but a low floor surfaces it (exact hit).
      final r = _q(lib, '7s 5s 2s', 'shallow', minMass: 1.0)!;
      expect(r.freqs['check'], closeTo(0.90, 1e-9));
      expect(r.textureFallback, 0);
    });

    test('unknown group (no cells for the hand class) → null', () {
      expect(_q(lib, 'As Kd 7h', 'shallow', hc: HandClass.strongMade), isNull);
    });

    test('pre-flop / too-short board → null', () {
      expect(_q(lib, 'As Kd', 'shallow'), isNull);
    });

    test('empty library is empty and never hits', () {
      final empty = GtoFrequencyLibrary.fromJson({'scenarios': {}});
      expect(empty.isEmpty, isTrue);
      expect(empty.lookup(
        scenario: 'srp_late_v_bb',
        board: _b('As Kd 7h'),
        sprBucket: 'shallow',
        street: 'flop',
        position: 'ip',
        facing: 'facing_check',
        handClass: HandClass.marginalMade,
      ), isNull);
    });
  });
}
