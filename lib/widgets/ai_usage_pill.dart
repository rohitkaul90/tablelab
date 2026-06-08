import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    final kindLabel = kind == AiAnalysisKind.session ? 'session' : 'hand';
    final String text;
    if (usage.exempt) {
      text = 'AI coaching · unlimited';
    } else {
      final used = kind == AiAnalysisKind.session ? usage.session : usage.hand;
      final limit = kind == AiAnalysisKind.session
          ? AiService.sessionDailyLimit
          : AiService.handDailyLimit;
      final remaining = (limit - used).clamp(0, limit);
      text = remaining > 0
          ? '$remaining free AI $kindLabel '
              '${remaining == 1 ? 'analysis' : 'analyses'} left today'
          : 'Daily AI $kindLabel limit reached — resets within 24h';
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
