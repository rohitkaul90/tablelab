import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/pack_manifest.dart';

/// The library stores only ONE suit-isomorphic representative per equivalent
/// runout, so availableTurnCards/availableRiverCards must report exactly the
/// stored cards — that set restricts the runout picker so the merged twins
/// (which have no node) can't be picked into a "no decisions" dead end.
void main() {
  PackManifest manifest(Iterable<String> chunkIds) => PackManifest.fromJson({
        'version': 1,
        'scenario': 'srp_late_v_bb',
        'spr': 'deep',
        'flop': '7s 5s 2s',
        'combos': {'oop': <String>[], 'ip': <String>[]},
        'chunks': {
          for (final id in chunkIds)
            id: {'file': '$id.bin.gz', 'nodes': 1, 'gz': 1},
        },
      });

  test('availableTurnCards lists only stored turn representatives', () {
    final m = manifest(['flop', 'turn/Ts', 'turn/9c', 'turn/9d', 'river/Ts9c']);
    expect(m.availableTurnCards(), {'Ts', '9c', '9d'});
    // 'flop' and river chunks are not turn cards.
    expect(m.availableTurnCards().contains('flop'), isFalse);
  });

  test('availableRiverCards keys off the stored turn card', () {
    final m = manifest([
      'turn/Ts',
      'river/Ts9c',
      'river/Ts9d',
      'river/Ts9s',
      // A different turn's rivers must NOT leak in.
      'river/2c9c',
    ]);
    // 9c/9d/9s are stored; the suit-equivalent 9h was merged away and absent.
    expect(m.availableRiverCards('Ts'), {'9c', '9d', '9s'});
    expect(m.availableRiverCards('Ts').contains('9h'), isFalse);
    expect(m.availableRiverCards('2c'), {'9c'});
  });

  test('an absent street yields an empty set (no runouts offered)', () {
    final m = manifest(['flop']);
    expect(m.availableTurnCards(), isEmpty);
    expect(m.availableRiverCards('Ts'), isEmpty);
  });
}
