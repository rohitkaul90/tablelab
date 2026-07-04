import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/grid_aggregation.dart';
import 'package:tablelab/explorer/pack_codec.dart';
import 'package:tablelab/widgets/explorer/combo_strategy_list.dart';

/// The combo boxes must lay out inside the Overview's ListView — a Row with
/// crossAxisAlignment.stretch there previously crashed (RenderFlex size MISSING
/// under an unbounded vertical axis); IntrinsicHeight bounds it.
void main() {
  testWidgets('renders combo boxes inside an unbounded ListView', (tester) async {
    final combos = [
      PackCombo(
          comboId: 0,
          reach: 1.0,
          equity: 0.5,
          evPassive: null,
          freqs: const [0.9, 0.1],
          evs: const []),
      PackCombo(
          comboId: 1,
          reach: 0.8,
          equity: 0.4,
          evPassive: null,
          freqs: const [0.5, 0.5],
          evs: const []),
      PackCombo(
          comboId: 2,
          reach: 0.6,
          equity: 0.3,
          evPassive: null,
          freqs: const [1.0, 0.0],
          evs: const []),
    ];
    final node = PackNode(
      path: '',
      street: 0,
      actorIsOop: true,
      potBefore: 10,
      toCall: 0,
      behind: 40,
      actions: const ['CHECK', 'BET 3'],
      combos: combos,
    );
    final cell = GridCellAgg(
      hand: 'A3s',
      comboCount: 3,
      maxCombos: 4,
      reach: 2.4,
      freqs: const [0.8, 0.2],
      equity: 0.4,
      combos: combos,
      dominantClass: null,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            ComboStrategyList(
              cell: cell,
              node: node,
              comboNames: const ['As3s', 'Ah3h', 'Ad3d'],
            ),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('90%'), findsOneWidget); // combo 0's dominant action
    expect(find.text('Bet 30%'), findsWidgets); // % of pot label
  });
}
