import 'package:flutter/material.dart';

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
            Text('≈ converted',
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
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Approximate totals'),
      content: Text(
        'Your sessions span multiple currencies, so totals here are converted '
        'to $currency at approximate exchange rates. Each session still shows '
        'its original currency.\n\n'
        'Pick a fixed display currency in Settings → Stats.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
