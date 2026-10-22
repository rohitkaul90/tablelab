import 'package:web/web.dart' as web;

/// Replaces the current history entry with the bare app URL so the recovery
/// `token_hash` is not kept in the address bar / history (a reload would
/// otherwise retry an already-consumed hash and surface a confusing error).
void clearRecoveryParamsFromAddressBar() {
  try {
    final loc = web.window.location;
    web.window.history.replaceState(null, '', '${loc.origin}/');
  } catch (_) {
    // Cosmetic; never let it break sign-in.
  }
}
