import 'package:web/web.dart' as web;

/// Removes ONLY the recovery params from the address bar, keeping the path,
/// any other query params, the fragment (Flutter's URL strategy lives there)
/// and the current `history.state` (Flutter's own entry marker — replacing it
/// with null would confuse its back-button handling), so a reload never
/// retries an already-consumed hash.
void clearRecoveryParamsFromAddressBar() {
  try {
    final current = Uri.parse(web.window.location.href);
    final query = Map<String, String>.from(current.queryParameters)
      ..remove('token_hash')
      ..remove('type');
    final href = StringBuffer(current.origin)
      ..write(current.path.isEmpty ? '/' : current.path);
    if (query.isNotEmpty) {
      href
        ..write('?')
        ..write(Uri(queryParameters: query).query);
    }
    if (current.hasFragment) {
      href
        ..write('#')
        ..write(current.fragment);
    }
    web.window.history
        .replaceState(web.window.history.state, '', href.toString());
  } catch (_) {
    // Cosmetic; never let it break sign-in.
  }
}
