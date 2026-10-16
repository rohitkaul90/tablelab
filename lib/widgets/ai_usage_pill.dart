import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/ai_service.dart';
import '../screens/settings_screen.dart';

/// Which daily AI quota a pill reflects.
enum AiAnalysisKind { session, hand }

/// A small, tappable indicator shown next to an "Analyze with AI" action.
///
/// Framed around what's *available* ("3 free AI analyses today") rather than
/// what's been consumed, so it nudges toward using the feature instead of
/// rationing it. Tapping opens Settings scrolled to the AI USAGE section.
/// Renders nothing while usage is still loading or if it failed, to avoid
/// flashing a misleading number.
class AiUsagePill extends ConsumerWidget {
  final AiAnalysisKind kind;

  const AiUsagePill({super.key, required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final usage = ref.watch(aiUsageProvider).valueOrNull;
    if (usage == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final isSession = kind == AiAnalysisKind.session;
    final String text;
    if (usage.exempt) {
      text = l10n.aiUsageUnlimited;
    } else {
      final used = kind == AiAnalysisKind.session ? usage.session : usage.hand;
      final limit = kind == AiAnalysisKind.session
          ? AiService.sessionDailyLimit
          : AiService.handDailyLimit;
      final remaining = (limit - used).clamp(0, limit);
      text = remaining > 0
          ? (isSession
              ? l10n.aiUsageSessionLeft(remaining)
              : l10n.aiUsageHandLeft(remaining))
          : (isSession
              ? l10n.aiUsageSessionLimitReached
              : l10n.aiUsageHandLimitReached);
    }

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SettingsScreen(scrollToSection: 'ai_usage'),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
