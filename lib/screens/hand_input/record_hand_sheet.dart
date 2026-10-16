import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'hand_input_screen.dart';
import 'quick_hand_screen.dart';

/// Lets the user choose Quick Hand vs the full street-by-street wizard, then
/// pushes the chosen screen. The returned future completes when the recording
/// screen pops, so call sites can keep their existing
/// `await …; if (!mounted) return; ref.invalidate(handsProvider);` shape.
Future<void> showRecordHandSheet(
  BuildContext context, {
  String? prefilledSessionId,
  String? prefilledStakes,
  String? prefilledSessionLabel,
  bool isTournamentSession = false,
}) async {
  final quick = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.bolt),
            title: Text(sheetCtx.l10n.recordHandQuickTitle),
            subtitle: Text(sheetCtx.l10n.recordHandQuickSubtitle),
            onTap: () => Navigator.pop(sheetCtx, true),
          ),
          ListTile(
            leading: const Icon(Icons.style_outlined),
            title: Text(sheetCtx.l10n.recordHandFullTitle),
            subtitle: Text(sheetCtx.l10n.recordHandFullSubtitle),
            onTap: () => Navigator.pop(sheetCtx, false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (quick == null || !context.mounted) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => quick
          ? QuickHandScreen(
              prefilledSessionId: prefilledSessionId,
              prefilledStakes: prefilledStakes,
              prefilledSessionLabel: prefilledSessionLabel,
              isTournamentSession: isTournamentSession,
            )
          : HandInputScreen(
              prefilledSessionId: prefilledSessionId,
              prefilledStakes: prefilledStakes,
              prefilledSessionLabel: prefilledSessionLabel,
              isTournamentSession: isTournamentSession,
            ),
    ),
  );
}
