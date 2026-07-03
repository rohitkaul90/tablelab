// GTO Explorer — the LINE-FIRST navigation ribbon: a horizontal breadcrumb of
// the current action line. Tap a step to rewind to just before it; the leading
// chip rewinds to the flop root. Advancing happens via the overview panel's
// action cards (design: launch/GTO_EXPLORER.md §4).

import 'package:flutter/material.dart';

import 'action_colors.dart';

class RibbonStep {
  final String actorLabel; // 'BB' / 'BTN'; empty for a chance step
  final String action; // raw solver label, or 'Turn Ah' / 'River 3d'
  final bool isChance;
  RibbonStep(this.actorLabel, this.action) : isChance = false;
  RibbonStep.chance(this.action)
      : actorLabel = '',
        isChance = true;
}

class ActionRibbon extends StatelessWidget {
  final String rootLabel; // e.g. 'Flop Ks 9h 4c'
  final List<RibbonStep> steps;
  final void Function(int keepSteps) onRewind;
  const ActionRibbon({
    super.key,
    required this.rootLabel,
    required this.steps,
    required this.onRewind,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(
            context,
            label: rootLabel,
            color: scheme.surfaceContainerHighest,
            textColor: scheme.onSurface,
            onTap: steps.isEmpty ? null : () => onRewind(0),
          ),
          for (var i = 0; i < steps.length; i++) ...[
            Center(
              child: Icon(Icons.chevron_right,
                  size: 16, color: scheme.onSurfaceVariant),
            ),
            _chip(
              context,
              label: steps[i].isChance
                  ? steps[i].action
                  : '${steps[i].actorLabel} ${actionDisplayLabel(steps[i].action)}',
              color: steps[i].isChance
                  ? scheme.tertiaryContainer.withValues(alpha: 0.55)
                  : actionColors([steps[i].action])
                      .first
                      .withValues(alpha: 0.28),
              textColor: scheme.onSurface,
              onTap: i == steps.length - 1 ? null : () => onRewind(i + 1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required Color color,
    required Color textColor,
    VoidCallback? onTap,
  }) {
    return Center(
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}
