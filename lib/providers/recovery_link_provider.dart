import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/recovery_link.dart';

/// Why the most recent sign-in / reset link failed, or null. Written by the
/// single app-level [recoveryLinkHandlerProvider]; `AuthGate` renders it on
/// the login screen (or as a SnackBar for a signed-in user) and clears it.
final authLinkErrorProvider = StateProvider<AuthLinkError?>((_) => null);

/// The ONE recovery-link handler for the app. `AuthGate` calls `start()` (which
/// is idempotent) — a second gate built by `MaterialApp.onUnknownRoute` shares
/// this instance instead of redeeming every link twice.
final recoveryLinkHandlerProvider = Provider<RecoveryLinkHandler>((ref) {
  final handler = RecoveryLinkHandler(
    verify: (hash) => Supabase.instance.client.auth
        .verifyOTP(type: OtpType.recovery, tokenHash: hash),
    onStatus: (status) =>
        ref.read(authLinkErrorProvider.notifier).state = status,
  );
  ref.onDispose(handler.dispose);
  return handler;
});
