// GTO Explorer — the Overview panel: who acts, pot state, range stats, the
// compact ACTION ROWS (one line each: frequency per action; tap filters the
// grid), and a HANDS section listing the SELECTED grid cell's combos (a hand +
// all its suits) with each combo's strategy. This panel INSPECTS; navigation
// lives up top (the ribbon rewinds, the strip advances).

import 'package:flutter/material.dart';

import '../../explorer/grid_aggregation.dart';
import '../../explorer/pack_codec.dart';
import 'action_colors.dart';
import 'combo_strategy_list.dart';

class OverviewPanel extends StatelessWidget {
  final PackNode node;
  final NodeSummary summary;
  final String actorLabel; // 'BB' / 'BTN'

  /// The action index currently filtering the grid (highlighted row).
  final int? selectedAction;
  final void Function(int actionIndex) onActionTap;

  /// bb per normalized pack unit (the solver scale pins the flop pot to 10).
  /// When non-null the pot/price show in big blinds; null (a scenario with no
  /// bb anchor) falls back to a pot-relative price.
  final double? bbPerUnit;

  /// The grid cell whose combos the HANDS section shows (tap a grid cell to
  /// select). Null → a hint. The acting position's combo names decode combos.
  final GridCellAgg? selectedCell;
  final List<String> comboNames;
  const OverviewPanel({
    super.key,
    required this.node,
    required this.summary,
    required this.actorLabel,
    required this.selectedAction,
    required this.onActionTap,
    required this.comboNames,
    this.bbPerUnit,
    this.selectedCell,
  });

  static String _fmtBB(double v) {
    final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return '${s}bb';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = actionColors(node.actions);

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
        // The pack solves in a normalized chip scale (flop pot pinned to 10,
        // stacks = SPR×10). With a bb anchor we show the pot/price in big
        // blinds; SPR is always the scale-free depth read.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (bbPerUnit != null && node.potBefore > 0)
              _stat(context, 'Pot', _fmtBB(node.potBefore * bbPerUnit!)),
            if (node.toCall > 0 && node.potBefore > 0)
              _stat(
                  context,
                  'To call',
                  bbPerUnit != null
                      ? _fmtBB(node.toCall * bbPerUnit!)
                      : '${(node.toCall / node.potBefore * 100).round()}% pot'),
            if (node.potBefore > 0)
              _stat(context, 'SPR',
                  (node.behind / node.potBefore).toStringAsFixed(1)),
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
          _actionRow(context, a, summary.actions[a], colors[a]),
        const SizedBox(height: 16),
        // HANDS — the selected cell's exact combos and their strategy.
        Row(
          children: [
            Text('HANDS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant, letterSpacing: 1.2)),
            if (selectedCell != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${selectedCell!.hand} · ${selectedCell!.comboCount} of '
                  '${selectedCell!.maxCombos} combos',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (selectedCell == null)
          Text('Tap a hand in the grid to see its exact combos and their '
              'strategy.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant))
        else if (selectedCell!.combos.isEmpty)
          Text('${selectedCell!.hand} has no live combos at this node.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant))
        else
          ComboStrategyList(
            cell: selectedCell!,
            node: node,
            comboNames: comboNames,
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

  /// One compact single-line action row: color dot · label · combos · freq% ·
  /// filter toggle. Tap filters the grid to the combos taking this action.
  Widget _actionRow(
      BuildContext context, int index, ActionAgg agg, Color color) {
    final scheme = Theme.of(context).colorScheme;
    final selected = selectedAction == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: color.withValues(alpha: selected ? 0.42 : 0.20),
        clipBehavior: Clip.antiAlias,
        // shape only — Material asserts if BOTH shape and borderRadius are set.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: selected ? BorderSide(color: color, width: 1.4) : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => onActionTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      actionSizeLabel(agg.label,
                          potBefore: node.potBefore, behind: node.behind),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                Text(agg.combos.toStringAsFixed(0),
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 10),
                Text('${(agg.freq * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                Icon(selected ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 15,
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
