import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/pack_source.dart';

class _NullSource implements PackSource {
  @override
  Future<Uint8List> read(String relPath) async => Uint8List(0);
}

/// ExplorerSpotRef identity: VALUE equality by [id], defaulting to the shared
/// sort key — two refs to the same spot from different discovery fetches must
/// compare equal (staleness guards, memo keys, the client LRU key).
void main() {
  ExplorerSpotRef ref({String spr = 'deep', String? id}) => ExplorerSpotRef(
        scenario: 'srp_late_v_bb',
        flop: '7s 5s 2s',
        spr: spr,
        source: _NullSource(),
        id: id,
      );

  test('id defaults to spotSortKey(scenario, flop, spr)', () {
    expect(ref().id, spotSortKey('srp_late_v_bb', '7s 5s 2s', 'deep'));
  });

  test('same spot from different sources compares equal (value ==)', () {
    final a = ref();
    final b = ref();
    expect(identical(a, b), isFalse);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('different spr → different spot', () {
    expect(ref(), isNot(ref(spr: 'medium')));
  });

  test('usable as a map key (the client LRU keys on it)', () {
    final m = <ExplorerSpotRef, int>{ref(): 1};
    expect(m[ref()], 1);
    expect(m[ref(spr: 'medium')], isNull);
  });

  test('an explicit id overrides the default', () {
    expect(ref(id: 'custom'), isNot(ref()));
    expect(ref(id: 'custom'), ref(spr: 'medium', id: 'custom'));
  });
}
