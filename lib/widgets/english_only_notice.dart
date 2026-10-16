import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// One localized line telling a non-English user that the document below is
/// English-only (owner decision: legal text is not machine-translated).
/// Renders nothing in an English UI.
class EnglishOnlyNotice extends StatelessWidget {
  const EnglishOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (isEnglishUi(l10n)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.translate, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.legalEnglishOnlyNotice,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
