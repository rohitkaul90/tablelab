// GTO Explorer — the Overview panel: who acts, pot state, range stats, and the
// ACTION CARDS (frequency / combos / EV per action). Tapping a card toggles an
// ACTION FILTER on the strategy grid (which combos take this action) — this
// panel INSPECTS; navigation lives up top (the ribbon rewinds, the advance
// bar advances).

import 'package:flutter/material.dart';

import '../../explorer/grid_aggregation.dart';
import '../../explorer/pack_codec.dart';
import 'action_colors.dart';

class OverviewPanel extends StatelessWidget {
  final PackNode node;
  final NodeSummary summary;
  final String actorLabel; // 'BB' / 'BTN'

  /// The action index currently filtering the grid (highlighted card).
  final int? selectedAction;
  final void Function(int actionIndex) onActionTap;
  const OverviewPanel({
    super.key,
    required this.node,
    required this.summary,
    required this.actorLabel,
    required this.selectedAction,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = actionColors(node.actions);
    final evAvailable = summary.actions.any((a) => a.evMean != null);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          '$actorLabel to act · ${node.actorIsOop ? 'OOP' : 'IP'}',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat(context, 'Pot', node.potBefore.toStringAsFixed(1)),
            if (node.toCall > 0)
              _stat(context, 'To call', node.toCall.toStringAsFixed(1)),
            _stat(context, 'Behind', node.behind.toStringAsFixed(1)),
            _stat(context, 'Combos', summary.totalReach.toStringAsFixed(1)),
            if (summary.equityMean != null)
              _stat(context, 'Equity',
                  '${(summary.equityMean! * 100).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 16),
        Text('ACTIONS · tap to filter the grid',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        for (var a = 0; a < summary.actions.length; a++)
          _actionCard(context, a, summary.actions[a], colors[a]),
        if (!evAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Per-action EV is available on flop root decisions only in this '
              'version.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: scheme.onSurfaceVariant)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _actionCard(
      BuildContext context, int index, ActionAgg agg, Color color) {
    final scheme = Theme.of(context).colorScheme;
    final selected = selectedAction == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: selected ? 0.45 : 0.22),
        clipBehavior: Clip.antiAlias,
        // shape only — Material asserts if BOTH shape and borderRadius are
        // set (crashed the whole Overview pane when a filter was selected).
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? BorderSide(color: color, width: 1.6)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => onActionTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(actionDisplayLabel(agg.label),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                        '${agg.combos.toStringAsFixed(1)} combos'
                        '${agg.evMean != null ? ' · EV ${agg.evMean!.toStringAsFixed(2)}' : ''}',
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text('${(agg.freq * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Icon(selected ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 18,
                    color:
                        selected ? scheme.onSurface : scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
