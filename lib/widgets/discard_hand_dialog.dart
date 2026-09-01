import 'package:flutter/material.dart';

/// Shared "discard in-progress hand?" confirmation used by both hand-recording
/// screens (full wizard + Quick Hand) for the AppBar close button, the system
/// back gesture, and the Quick→Full mode switch.
Future<bool> confirmDiscardHand(
  BuildContext context, {
  String title = 'Discard hand?',
  String message = 'This hand will not be saved.',
  String confirmLabel = 'Discard',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: const TextStyle(color: Colors.red))),
      ],
    ),
  );
  return ok == true;
}
