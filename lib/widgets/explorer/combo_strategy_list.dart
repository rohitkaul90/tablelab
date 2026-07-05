// GTO Explorer — the Hands panel's combo BOXES for the hovered grid cell (a
// hand + all its suits), laid out two per row like GTO Wizard. Each box shows
// the suit-colored combo and its per-action strategy frequencies (e.g.
// "Check 90% / Bet 33% 10%") over a thin stacked bar. No scrollable of its own
// — it sits inside the Overview panel's ListView.

import 'package:flutter/material.dart';

import '../../equity/card.dart';
import '../../explorer/grid_aggregation.dart';
import '../../explorer/pack_codec.dart';
import 'action_colors.dart';

class ComboStrategyList extends StatelessWidget {
  final GridCellAgg cell;
  final PackNode node;
  final List<String> comboNames;
  const ComboStrategyList({
    super.key,
    required this.cell,
    required this.node,
    required this.comboNames,
  });

  static const _suitColors = {
    0: Color(0xFF6FBF73), // c
    1: Color(0xFF64A5E8), // d
    2: Color(0xFFE57373), // h
    3: Color(0xFFE0E0E0), // s
  };

  static String _pct(double f) {
    final v = f * 100;
    return v == v.roundToDouble() ? '${v.round()}%' : '${v.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final colors = actionColors(node.actions);
    final combos = [...cell.combos]..sort((a, b) => b.reach.compareTo(a.reach));
    // Two boxes per row.
    final rows = <Widget>[];
    for (var i = 0; i < combos.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        // IntrinsicHeight bounds the row's height so the two boxes can stretch
        // to equal height — a bare stretch inside the ListView's unbounded
        // vertical axis crashes (RenderFlex size MISSING / h<=Infinity).
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _box(context, combos[i], colors)),
              const SizedBox(width: 8),
              if (i + 1 < combos.length)
                Expanded(child: _box(context, combos[i + 1], colors))
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _box(BuildContext context, PackCombo c, List<Color> colors) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        c.comboId < comboNames.length ? comboNames[c.comboId] : '#${c.comboId}';
    // Actions taken, dominant first.
    final taken = [
      for (var a = 0; a < c.freqs.length && a < node.actions.length; a++)
        if (c.freqs[a] > 0) a
    ]..sort((a, b) => c.freqs[b].compareTo(c.freqs[a]));
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(name),
          const SizedBox(height: 6),
          for (final a in taken)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: colors[a], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                        actionSizeLabel(node.actions[a],
                            potBefore: node.potBefore,
                            toCall: node.toCall,
                            behind: node.behind),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                  Text(_pct(c.freqs[a]),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          // Thin stacked strategy bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                for (var a = 0; a < c.freqs.length && a < colors.length; a++)
                  if (c.freqs[a] > 0)
                    Expanded(
                      flex: (c.freqs[a] * 1000).round(),
                      child: ColoredBox(color: colors[a]),
                    ),
                if (taken.isEmpty)
                  Expanded(
                      child: ColoredBox(color: scheme.surfaceContainerHighest)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String name) {
    if (name.length != 4) return Text(name);
    return RichText(
      text: TextSpan(children: [
        for (final part in [name.substring(0, 2), name.substring(2, 4)])
          TextSpan(
            text: '${part[0]}${kSuitSymbols[kSuitChars.indexOf(part[1])]}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _suitColors[kSuitChars.indexOf(part[1])],
            ),
          ),
      ]),
    );
  }
}
