import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/ai_service.dart';

/// The footer under every AI coaching result (hand + session screens).
///
/// Always shows the "AI coaching can be wrong" disclaimer. In any non-English
/// UI it adds a second line saying the coaching itself is still English: the
/// app chrome is localized, but the AI-written text isn't yet (that's phase 2,
/// a `language` field on the Edge Functions). Remove the second line then.
class AiDisclaimerFooter extends StatelessWidget {
  const AiDisclaimerFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        );
    final english = Localizations.localeOf(context).languageCode == 'en';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(l10n.aiDisclaimer, textAlign: TextAlign.center, style: style),
          if (!english) ...[
            const SizedBox(height: 4),
            Text(l10n.aiCoachingEnglishNote,
                textAlign: TextAlign.center, style: style),
          ],
        ],
      ),
    );
  }
}

/// Localized (title, body) for a failed AI call. The English UI keeps the
/// Edge Function's own message (it's specific and already English); other
/// languages get a localized body because the server text is English-only.
({String title, String body}) aiErrorText(AppLocalizations l10n, Object e) {
  final english = l10n.localeName.startsWith('en');
  if (e is AiException) {
    if (e.isRateLimited) {
      return (
        title: l10n.aiDailyLimitTitle,
        body: english ? e.message : l10n.aiErrorDailyLimitBody,
      );
    }
    if (e.isAtCapacity) {
      return (
        title: l10n.aiAtCapacityTitle,
        body: english ? e.message : l10n.aiErrorAtCapacityBody,
      );
    }
    return (
      title: l10n.aiAnalysisFailed,
      body: english ? e.message : l10n.aiErrorGeneric,
    );
  }
  return (title: l10n.aiAnalysisFailed, body: l10n.aiErrorGeneric);
}
