import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// Read-only banner shown when a hand is being recorded from a locked session
/// (the session was prefilled by the caller and can't be changed).
class LinkedSessionBanner extends StatelessWidget {
  final String? label;
  const LinkedSessionBanner({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label != null ? 'Linked to: $label' : 'Linked to session',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dropdown that links a hand to one of the user's recent sessions (or none).
/// Used by both the full wizard and Quick Hand mode. Theme-token based so it
/// reads correctly under the ambient (light/dark) theme as well as the
/// wizard's forced-dark felt theme.
class SessionPickerTile extends ConsumerWidget {
  final String? selectedSessionId;
  final ValueChanged<String?> onChanged;

  const SessionPickerTile({
    super.key,
    required this.selectedSessionId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final sessionsAsync = ref.watch(sessionsProvider);

    return sessionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (sessions) {
        // A live (in-progress) session isn't a valid link target yet.
        final selectable = sessions.where((s) => !s.isLive).toList();
        if (selectable.isEmpty) return const SizedBox.shrink();

        final sorted = [...selectable]
          ..sort((a, b) => b.date.compareTo(a.date));
        final recent = sorted.take(20).toList();

        final selected = selectedSessionId != null
            ? recent.where((s) => s.id == selectedSessionId).firstOrNull
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Link to Session (optional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: selectedSessionId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              hint: const Text('None'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                ...recent.map((s) {
                  final date =
                      s.date.length >= 10 ? s.date.substring(0, 10) : s.date;
                  final loc = (s.location != null && s.location!.isNotEmpty)
                      ? '  ·  ${s.location}'
                      : '';
                  // Location distinguishes multiple same-day sessions at
                  // different venues.
                  final label = '$date  ·  ${s.gameType}  ·  ${s.stakes}$loc';
                  return DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  );
                }),
              ],
              onChanged: onChanged,
            ),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  'Session: ${selected.date.substring(0, 10)}  ·  ${selected.stakes}'
                  '${selected.location != null && selected.location!.isNotEmpty ? '  ·  ${selected.location}' : ''}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ),
          ],
        );
      },
    );
  }
}
