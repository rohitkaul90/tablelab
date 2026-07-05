import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/grid_aggregation.dart';
import 'package:tablelab/explorer/pack_codec.dart';
import 'package:tablelab/widgets/explorer/overview_panel.dart';

/// The Overview lays out the horizontal actions row + the Hands box grid
/// without overflow; on the Equity-chart tab a [headerChart] replaces the stat
/// box above the actions.
void main() {
  final combos = [
    PackCombo(
        comboId: 0,
        reach: 1.0,
        equity: 0.5,
        evPassive: null,
        freqs: const [0.6, 0.4],
        evs: const []),
    PackCombo(
        comboId: 1,
        reach: 0.7,
        equity: 0.4,
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
  final summary = NodeSummary(
    1.7,
    [ActionAgg('CHECK', 0.65, 1.1, null), ActionAgg('BET 3', 0.35, 0.6, null)],
    0.5,
  );
  final cell = GridCellAgg(
    hand: 'A3s',
    comboCount: 2,
    maxCombos: 4,
    reach: 1.7,
    freqs: const [0.6, 0.4],
    equity: 0.4,
    combos: combos,
    dominantClass: null,
  );

  Future<void> pump(WidgetTester tester, {Widget? headerChart}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: OverviewPanel(
              node: node,
              summary: summary,
              actorLabel: 'BB',
              selectedAction: null,
              onActionTap: (_) {},
              comboNames: const ['As3s', 'Ah3h'],
              selectedCell: cell,
              bbPerUnit: 0.55,
              headerChart: headerChart,
            ),
          ),
        ),
      ));

  testWidgets('renders actions row + hands grid (stat box shown)',
      (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('SPR'), findsOneWidget); // the stat box
    expect(find.text('Check'), findsWidgets); // action box label
    expect(find.text('Bet 30%'), findsWidgets); // % of pot, not the raw "3"
  });

  testWidgets('headerChart replaces the stat box above the actions',
      (tester) async {
    await pump(tester,
        headerChart: const SizedBox(height: 180, key: Key('chart')));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('chart')), findsOneWidget);
    expect(find.text('SPR'), findsNothing); // stat box hidden
    expect(find.text('Check'), findsWidgets); // actions still present
  });

  testWidgets('embedded mode adds no scrollable of its own (single scroll)',
      (tester) async {
    // The narrow layout wraps the embedded panel in ONE outer ListView; the
    // panel must NOT add a second (that nesting stuck the user at the bottom).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 380,
          child: ListView(children: [
            OverviewPanel(
              node: node,
              summary: summary,
              actorLabel: 'BB',
              selectedAction: null,
              onActionTap: (_) {},
              comboNames: const ['As3s', 'Ah3h'],
              selectedCell: cell,
              bbPerUnit: 0.55,
              embedded: true,
            ),
          ]),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsOneWidget); // only the outer ListView
    expect(find.text('Check'), findsWidgets);
  });
}
