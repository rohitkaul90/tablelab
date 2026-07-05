// GTO Explorer — the PREFLOP decision body: the acting player's PRESET range
// on the 13×13 grid + the action panel (combo counts, "% of hands" shares,
// filter cards). The trail itself (who opened / responded) lives in the
// UNIFIED line strip up top (gto_explorer_screen); this renders one decision.
//
// Honesty note: presets are RANGES, not mixed solver frequencies — a hand is
// in or out; overlaps resolve 4-bet > call, 3-bet > call.

import 'package:flutter/material.dart';

import '../../explorer/preflop_ranges.dart';
import 'strategy_grid.dart';

/// UI colors for the preflop action vocabulary (dark-calibrated, matching the
/// postflop action-color families).
const Map<String, Color> kPreflopActionColors = {
  'Raise': Color(0xFFA23030),
  '3-bet': Color(0xFFA23030),
  '4-bet': Color(0xFF8C2323),
  'Call': Color(0xFF3E9B4F),
  'Fold': Color(0xFF4A7BB5),
};

class PreflopDecisionBody extends StatefulWidget {
  final PreflopDecision decision;
  final String subtitle; // e.g. 'vs the BTN open'
  const PreflopDecisionBody(
      {super.key, required this.decision, required this.subtitle});

  @override
  State<PreflopDecisionBody> createState() => _PreflopDecisionBodyState();
}

class _PreflopDecisionBodyState extends State<PreflopDecisionBody> {
  int? _filterAction;

  @override
  void didUpdateWidget(PreflopDecisionBody old) {
    super.didUpdateWidget(old);
    if (old.decision.actorLabel != widget.decision.actorLabel ||
        old.decision.actions.length != widget.decision.actions.length) {
      _filterAction = null; // indices are per decision
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decision;
    final grid = _grid(context, d);
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 11, child: grid),
            const VerticalDivider(width: 1),
            Expanded(flex: 9, child: _actionPanel(context, d)),
          ],
        );
      }
      // ONE outer scroll — the panel renders as a Column here so its own
      // ListView can't trap the gesture (the nested-scroll stuck-at-bottom bug).
      return ListView(
          children: [grid, _actionPanel(context, d, embedded: true)]);
    });
  }

  Widget _grid(BuildContext context, PreflopDecision d) {
    final cells = preflopGridCells(d);
    final colors = [
      for (final a in d.actions) kPreflopActionColors[a] ?? Colors.grey
    ];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, c) {
        final side = !c.maxHeight.isFinite
            ? c.maxWidth
            : [c.maxWidth, c.maxHeight]
                .reduce((a, b) => a < b ? a : b)
                .clamp(120.0, 4096.0);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: StrategyGrid(
              cells: cells,
              actionColors: colors,
              filterAction: _filterAction,
            ),
          ),
        );
      }),
    );
  }

  Widget _actionPanel(BuildContext context, PreflopDecision d,
      {bool embedded = false}) {
    final scheme = Theme.of(context).colorScheme;
    final shares = d.shares;
    final combos = d.comboCounts;
    final children = <Widget>[
      Text('${d.actorLabel} — ${widget.subtitle}',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Text('ACTIONS · % of hands · tap to filter the grid',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant, letterSpacing: 1.2)),
      const SizedBox(height: 6),
      for (var a = 0; a < d.actions.length; a++)
        _actionCard(context, a, d.actions[a],
            kPreflopActionColors[d.actions[a]] ?? Colors.grey, shares[a],
            combos[a]),
      const SizedBox(height: 8),
      Text(
        'Preset ranges — a hand is in or out; percentages are each '
        'action\'s share of hands, not mixed frequencies.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10.5),
      ),
    ];
    if (embedded) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
    }
    return ListView(padding: const EdgeInsets.all(12), children: children);
  }

  Widget _actionCard(BuildContext context, int index, String label,
      Color color, double share, int comboCount) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filterAction == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: selected ? 0.45 : 0.22),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? BorderSide(color: color, width: 1.6)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => setState(
              () => _filterAction = _filterAction == index ? null : index),
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
                      Text(label,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('$comboCount combos',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text('${(share * 100).toStringAsFixed(1)}%',
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
