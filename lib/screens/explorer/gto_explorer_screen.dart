// GTO Explorer ("Study") — Phase 1 MVP: browse the solved GTO library's spots
// visually. FLOP street only (turn/river = Phase 2); spots come from a local
// packs directory in dev (hosted packs = the Phase 1 hosting step).
// Design: launch/GTO_EXPLORER.md §4. Line-first navigation: the ribbon rewinds,
// the overview panel's action cards advance.
//
// Wrapped in AppTheme.dark like the other solver/felt screens — the action
// colors are dark-calibrated and it bounds the theming work.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../explorer/grid_aggregation.dart';
import '../../explorer/pack_codec.dart';
import '../../explorer/scenario_labels.dart';
import '../../providers/explorer_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/explorer/action_colors.dart';
import '../../widgets/explorer/action_ribbon.dart';
import '../../widgets/explorer/overview_panel.dart';
import '../../widgets/explorer/strategy_grid.dart';

class GtoExplorerScreen extends ConsumerStatefulWidget {
  final bool showScaffold;
  const GtoExplorerScreen({super.key, this.showScaffold = true});

  @override
  ConsumerState<GtoExplorerScreen> createState() => _GtoExplorerScreenState();
}

class _GtoExplorerScreenState extends ConsumerState<GtoExplorerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(explorerProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = Theme(
      data: AppTheme.dark,
      child: Builder(builder: (context) {
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: _body(context),
        );
      }),
    );
    if (!widget.showScaffold) return body;
    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        appBar: AppBar(title: const Text('GTO Study')),
        body: body,
      ),
    );
  }

  Widget _body(BuildContext context) {
    final state = ref.watch(explorerProvider);
    final scheme = Theme.of(context).colorScheme;

    if (state.scanning) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.spots.isEmpty) {
      return _message(
        context,
        icon: Icons.school_outlined,
        title: 'No solved spots available yet',
        body: 'GTO Study browses solver solutions of common preflop '
            'scenarios. Solution packs are being rolled out — check back '
            'soon.\n\n(Developer: place packs under ~/tlpacks or pass '
            '--dart-define=TLPACKS_DIR=<dir>.)',
      );
    }
    if (state.error != null) {
      return _message(context,
          icon: Icons.error_outline, title: 'Something went wrong',
          body: state.error!);
    }

    return Column(
      children: [
        _spotHeader(context, state),
        const Divider(height: 1),
        if (state.loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (state.manifest != null && state.flopNodes != null)
          Expanded(child: _loaded(context, state))
        else
          Expanded(
            child: _message(context,
                icon: Icons.hourglass_empty,
                title: 'Select a spot',
                body: 'Pick a flop + stack depth above.'),
          ),
        // Beta footer — honest scope framing (26 solved flops per depth).
        Container(
          width: double.infinity,
          color: scheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            'Beta · flop decisions · solved to ≤0.5% exploitability on '
            'representative boards',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10.5),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _spotHeader(BuildContext context, ExplorerState state) {
    final scenarios =
        state.spots.map((s) => s.scenario).toSet().toList()..sort();
    final scenario = state.spot?.scenario ?? scenarios.first;
    final inScenario =
        state.spots.where((s) => s.scenario == scenario).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (scenarios.length > 1) ...[
            Expanded(
              flex: 5,
              child: _dropdown<String>(
                context,
                value: scenario,
                items: [
                  for (final sc in scenarios)
                    DropdownMenuItem(
                        value: sc, child: Text(scenarioDisplayName(sc))),
                ],
                onChanged: (sc) {
                  final first = state.spots.firstWhere(
                      (s) => s.scenario == sc,
                      orElse: () => state.spots.first);
                  ref.read(explorerProvider.notifier).selectSpot(first);
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 4,
            child: _dropdown(
              context,
              value: state.spot,
              items: [
                for (final s in inScenario)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) {
                if (s != null) {
                  ref.read(explorerProvider.notifier).selectSpot(s);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(),
      ),
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _loaded(BuildContext context, ExplorerState state) {
    final manifest = state.manifest!;
    final node = state.currentNode;
    final steps = _ribbonSteps(state);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: ActionRibbon(
            rootLabel: 'Flop ${manifest.flop}',
            steps: steps,
            onRewind: (n) => ref.read(explorerProvider.notifier).popTo(n),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: node == null
              ? _streetClosed(context, state)
              : _nodeView(context, state, node),
        ),
      ],
    );
  }

  List<RibbonStep> _ribbonSteps(ExplorerState state) {
    // Actor of step i = actor of the node the first i steps lead to; the flop
    // root is always OOP and actors strictly alternate within a street.
    final scenario = state.manifest?.scenario ?? '?';
    return [
      for (var i = 0; i < state.path.length; i++)
        RibbonStep(
          seatLabel(scenario, isOop: i.isEven),
          state.path[i],
        ),
    ];
  }

  Widget _nodeView(BuildContext context, ExplorerState state, PackNode node) {
    final manifest = state.manifest!;
    final combos = manifest.combosFor(oop: node.actorIsOop);
    final cells = aggregateGrid(node, combos);
    final summary = summarizeNode(node);
    final colors = actionColors(node.actions);
    final actor =
        seatLabel(manifest.scenario, isOop: node.actorIsOop);

    final grid = Padding(
      padding: const EdgeInsets.all(8),
      child: StrategyGrid(cells: cells, actionColors: colors),
    );
    final overview = OverviewPanel(
      node: node,
      summary: summary,
      actorLabel: actor,
      onAction: (a) => ref.read(explorerProvider.notifier).push(a),
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 11, child: grid),
            const VerticalDivider(width: 1),
            Expanded(flex: 9, child: overview),
          ],
        );
      }
      return ListView(
        children: [
          grid,
          SizedBox(
            height: 420,
            child: OverviewPanel(
              node: node,
              summary: summary,
              actorLabel: actor,
              onAction: (a) => ref.read(explorerProvider.notifier).push(a),
            ),
          ),
        ],
      );
    });
  }

  Widget _streetClosed(BuildContext context, ExplorerState state) {
    final last = state.path.isNotEmpty ? state.path.last.toUpperCase() : '';
    final folded = last.startsWith('FOLD');
    return _message(
      context,
      icon: folded ? Icons.close : Icons.arrow_forward,
      title: folded ? 'Hand over — fold' : 'Flop action complete',
      body: folded
          ? 'This line ends the hand. Rewind with the chips above to explore '
              'a different line.'
          : 'This line closes the flop. Turn and river navigation are coming '
              'in the next version — rewind with the chips above to explore '
              'other flop lines.',
      action: TextButton(
        onPressed: () => ref
            .read(explorerProvider.notifier)
            .popTo(state.path.length - 1),
        child: const Text('Back one step'),
      ),
    );
  }

  Widget _message(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ),
    );
  }
}
