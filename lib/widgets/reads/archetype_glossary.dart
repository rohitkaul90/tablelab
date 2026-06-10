import 'package:flutter/material.dart';
import '../../reads/tag_definitions.dart';

/// Bottom sheet that explains each player-type archetype in plain language.
/// Opened from the ⓘ next to the tag pickers (quick-add sheet, read detail).
void showArchetypeGlossary(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.92,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 24 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Text('Player Types', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'What each tag means — pick the one that best fits how they play.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final e in kArchetypeTags.entries) ...[
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: readableTagColor(ctx, tagColor(e.key)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(e.value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 18, bottom: 16),
                child: Text(
                  kArchetypeDefinitions[e.key] ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
