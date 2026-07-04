// GTO Explorer — the per-combo strategy list for a selected grid cell: a hand
// and all its suit combos, each with its strategy mix as a stacked bar plus the
// per-action frequency (colored to match the actions above). Has NO scrollable
// of its own — it sits inside the Overview panel's ListView.

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

  @override
  Widget build(BuildContext context) {
    final colors = actionColors(node.actions);
    final combos = [...cell.combos]..sort((a, b) => b.reach.compareTo(a.reach));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final c in combos) _row(context, c, colors)],
    );
  }

  Widget _row(BuildContext context, PackCombo c, List<Color> colors) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        c.comboId < comboNames.length ? comboNames[c.comboId] : '#${c.comboId}';
    final hasFreq = c.freqs.any((f) => f > 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 46, child: _label(name)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 12,
                child: Row(children: [
                  for (var a = 0; a < c.freqs.length && a < colors.length; a++)
                    if (c.freqs[a] > 0)
                      Expanded(
                        flex: (c.freqs[a] * 1000).round(),
                        child: ColoredBox(color: colors[a]),
                      ),
                  if (!hasFreq)
                    Expanded(
                        child:
                            ColoredBox(color: scheme.surfaceContainerHighest)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Per-action frequency, colored to match the bar / the actions above.
          SizedBox(
            width: 74,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              children: [
                for (var a = 0; a < c.freqs.length && a < colors.length; a++)
                  if (c.freqs[a] > 0)
                    Text('${(c.freqs[a] * 100).round()}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: colors[a])),
              ],
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
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _suitColors[kSuitChars.indexOf(part[1])],
            ),
          ),
      ]),
    );
  }
}
