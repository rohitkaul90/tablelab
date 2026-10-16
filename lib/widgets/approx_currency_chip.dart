import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Small, tappable indicator shown once per card/section (NOT per number) when
/// the on-screen totals span multiple currencies and are therefore FX-converted
/// to [currency] at approximate static rates. Tapping explains it and points at
/// the Settings display-currency control.
class ApproxCurrencyChip extends StatelessWidget {
  final String currency;
  const ApproxCurrencyChip({super.key, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showApproxCurrencyInfo(context, currency),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.approxConverted,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: c, fontWeight: FontWeight.w600)),
            const SizedBox(width: 3),
            Icon(Icons.info_outline, size: 13, color: c),
          ],
        ),
      ),
    );
  }
}

Future<void> showApproxCurrencyInfo(BuildContext context, String currency) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.approxTitle),
      content: Text(l10n.approxBody(currency)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonGotIt),
        ),
      ],
    ),
  );
}
