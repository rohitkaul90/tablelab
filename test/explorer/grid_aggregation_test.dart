import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/grid_aggregation.dart';
import 'package:tablelab/explorer/pack_codec.dart';

PackNode _node(List<PackCombo> combos) => PackNode(
      path: '',
      street: 0,
      actorIsOop: true,
      potBefore: 10,
      toCall: 0,
      behind: 30,
      actions: ['CHECK', 'BET 5'],
      combos: combos,
    );

PackCombo _combo(int id, double reach, List<double> freqs,
        {double? equity, List<double?>? evs}) =>
    PackCombo(
      comboId: id,
      reach: reach,
      equity: equity,
      evPassive: null,
      freqs: freqs,
      evs: evs ?? const [null, null],
    );

void main() {
  // Registry: 0 = AhKh (AKs), 1 = AdKc (AKo), 2 = QdQc (QQ), 3 = AsKs (AKs).
  const names = ['AhKh', 'AdKc', 'QdQc', 'AsKs'];

  group('comboCell', () {
    test('maps suited, offsuit, and pairs to the right matrix cells', () {
      expect(comboCell('AhKh'), (0, 1)); // AKs upper triangle
      expect(comboCell('AdKc'), (1, 0)); // AKo lower triangle
      expect(comboCell('QdQc'), (2, 2)); // QQ diagonal
      expect(comboCell('bogus'), isNull);
    });
  });

  group('aggregateGrid', () {
    test('reach-weights freqs within a cell and tracks presence', () {
      final grid = aggregateGrid(
        _node([
          // Two AKs combos with different mixes: 1.0×(100% check) and
          // 0.5×(100% bet) → cell mix check 2/3, bet 1/3; reach 1.5 of max 4.
          _combo(0, 1.0, [1.0, 0.0], equity: 0.5),
          _combo(3, 0.5, [0.0, 1.0], equity: 0.9),
          _combo(2, 1.0, [0.6, 0.4]),
        ]),
        names,
      );
      final aks = grid[0][1]!;
      expect(aks.hand, 'AKs');
      expect(aks.comboCount, 2);
      expect(aks.maxCombos, 4);
      expect(aks.reach, closeTo(1.5, 1e-9));
      expect(aks.presence, closeTo(1.5 / 4, 1e-9));
      expect(aks.freqs[0], closeTo(1.0 / 1.5, 1e-9)); // check
      expect(aks.freqs[1], closeTo(0.5 / 1.5, 1e-9)); // bet
      // Equity: (1.0·0.5 + 0.5·0.9) / 1.5
      expect(aks.equity, closeTo(0.95 / 1.5, 1e-9));

      expect(grid[2][2]!.hand, 'QQ');
      expect(grid[2][2]!.equity, isNull); // no equity data on that combo
      expect(grid[5][5], isNull); // no 99 in the node
    });
  });

  group('summarizeNode', () {
    test('action mix, combos, and EV are reach·freq-weighted', () {
      final s = summarizeNode(_node([
        _combo(0, 1.0, [1.0, 0.0], evs: [2.0, null]),
        _combo(1, 1.0, [0.0, 1.0], evs: [null, 4.0]),
        _combo(2, 2.0, [0.5, 0.5], evs: [1.0, 2.0]),
      ]));
      expect(s.totalReach, closeTo(4.0, 1e-9));
      // check mass = 1.0 + 1.0 = 2.0; bet mass = 1.0 + 1.0 = 2.0.
      expect(s.actions[0].freq, closeTo(0.5, 1e-9));
      expect(s.actions[0].combos, closeTo(2.0, 1e-9));
      expect(s.actions[1].combos, closeTo(2.0, 1e-9));
      // check EV: (1.0·2.0 + 1.0·1.0) / 2.0 = 1.5
      expect(s.actions[0].evMean, closeTo(1.5, 1e-9));
      // bet EV: (1.0·4.0 + 1.0·2.0) / 2.0 = 3.0
      expect(s.actions[1].evMean, closeTo(3.0, 1e-9));
    });

    test('EV is null when absent everywhere (turn/river nodes today)', () {
      final s = summarizeNode(_node([
        _combo(0, 1.0, [0.7, 0.3]),
      ]));
      expect(s.actions[0].evMean, isNull);
      expect(s.actions[1].evMean, isNull);
    });
  });
}
