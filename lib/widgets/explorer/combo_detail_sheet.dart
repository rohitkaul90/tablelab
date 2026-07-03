// GTO Explorer — per-combo drill-down: tap a grid cell → this bottom sheet
// lists the cell's live combos with reach, the strategy mix as a stacked bar,
// per-action EV (when the pack carries it — flop decisions today), and equity.

import 'package:flutter/material.dart';

import '../../equity/card.dart';
import '../../explorer/grid_aggregation.dart';
import '../../explorer/pack_codec.dart';
import 'action_colors.dart';

void showComboDetailSheet(
  BuildContext context, {
  required GridCellAgg cell,
  required PackNode node,
  required List<String> comboNames,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, controller) => _ComboList(
        cell: cell,
        node: node,
        comboNames: comboNames,
        controller: controller,
      ),
    ),
  );
}

class _ComboList extends StatelessWidget {
  final GridCellAgg cell;
  final PackNode node;
  final List<String> comboNames;
  final ScrollController controller;
  const _ComboList({
    required this.cell,
    required this.node,
    required this.comboNames,
    required this.controller,
  });

  static const _suitColors = {
    0: Color(0xFF6FBF73), // c
    1: Color(0xFF64A5E8), // d
    2: Color(0xFFE57373), // h
    3: Color(0xFFE0E0E0), // s
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = actionColors(node.actions);
    final combos = [...cell.combos]..sort((a, b) => b.reach.compareTo(a.reach));
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('${cell.hand} · ${cell.comboCount} of ${cell.maxCombos} combos '
            'live · ${cell.reach.toStringAsFixed(2)} reach',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          children: [
            for (var a = 0; a < node.actions.length; a++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: colors[a], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(actionDisplayLabel(node.actions[a]),
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ]),
          ],
        ),
        const SizedBox(height: 10),
        for (final c in combos) _comboRow(context, c, colors),
      ],
    );
  }

  Widget _comboRow(BuildContext context, PackCombo c, List<Color> colors) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        c.comboId < comboNames.length ? comboNames[c.comboId] : '#${c.comboId}';
    final evParts = <String>[];
    for (var a = 0; a < node.actions.length && a < c.evs.length; a++) {
      final ev = c.evs[a];
      if (ev != null) {
        evParts.add(
            '${actionDisplayLabel(node.actions[a])} ${ev.toStringAsFixed(2)}');
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 52, child: _comboLabel(name)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Strategy mix as a slim stacked bar.
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 10,
                    child: Row(children: [
                      for (var a = 0;
                          a < c.freqs.length && a < colors.length;
                          a++)
                        if (c.freqs[a] > 0)
                          Expanded(
                            flex: (c.freqs[a] * 1000).round(),
                            child: ColoredBox(color: colors[a]),
                          ),
                      if (c.freqs.every((f) => f <= 0))
                        Expanded(
                            child: ColoredBox(
                                color: scheme.surfaceContainerHighest)),
                    ]),
                  ),
                ),
                if (evParts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('EV: ${evParts.join(' · ')}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('reach ${(c.reach * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 10.5, color: scheme.onSurfaceVariant)),
                if (c.equity != null)
                  Text('eq ${(c.equity! * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comboLabel(String name) {
    if (name.length != 4) return Text(name);
    return RichText(
      text: TextSpan(children: [
        for (final part in [name.substring(0, 2), name.substring(2, 4)])
          TextSpan(
            text: '${part[0]}${kSuitSymbols[kSuitChars.indexOf(part[1])]}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _suitColors[kSuitChars.indexOf(part[1])],
            ),
          ),
      ]),
    );
  }
}
