import 'package:flutter/material.dart';

import '../models/session_model.dart';
import '../screens/ai_analysis/session_analysis_screen.dart';
import 'ai_usage_pill.dart';

/// "Get AI coaching" CTA card — the dashboard's entry point into the AI
/// session-analysis funnel. Lives in the Stats Summary tab (and the
/// flag-gated legacy Overview tab). Pass the user's LATEST session:
/// `([...sessions]..sort((a, b) => b.date.compareTo(a.date))).first`.
class AiCoachingCard extends StatelessWidget {
  final SessionModel session;
  const AiCoachingCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SessionAnalysisScreen(session: session)),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.6),
                scheme.surface,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Get AI coaching',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: scheme.primary)),
                    const SizedBox(height: 2),
                    Text('Analyse your latest session for leaks & insights.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            )),
                    const SizedBox(height: 4),
                    const AiUsagePill(kind: AiAnalysisKind.session),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: scheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
