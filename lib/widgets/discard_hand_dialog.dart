import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Shared "discard in-progress hand?" confirmation used by both hand-recording
/// screens (full wizard + Quick Hand) for the AppBar close button, the system
/// back gesture, and the Quick→Full mode switch. The texts default to the
/// localized discard-hand copy; callers pass overrides for other flows (e.g.
/// the Quick→Full switch).
Future<bool> confirmDiscardHand(
  BuildContext context, {
  String? title,
  String? message,
  String? confirmLabel,
}) async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? l10n.discardHandTitle),
      content: Text(message ?? l10n.discardHandMessage),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? l10n.discardHandConfirm,
                style: const TextStyle(color: Colors.red))),
      ],
    ),
  );
  return ok == true;
}
