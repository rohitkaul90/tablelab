/// Password-recovery links that work from ANY device.
///
/// Background: the SDK runs the PKCE flow, so the link Supabase's default
/// "Reset Password" template produces carries a one-time `code` that only the
/// client holding the matching code verifier can redeem. A reset requested
/// from the iPhone app and opened in a browser (the normal case — the email
/// lands in a mail client, not in the app) therefore failed with
/// "Code verifier could not be found in local storage", and the gate showed a
/// permanent splash (2026-10-22).
///
/// The fix has two halves:
///  * The recovery email template points at `https://tablelab.app/reset.html`
///    carrying `token_hash={{ .TokenHash }}&type=recovery`. That static page
///    offers "Open the TableLab app" (deep link, same query) or "Continue on
///    the web" (`https://tablelab.app/?token_hash=…&type=recovery`).
///  * This module watches both entry points (the web app's initial URL and the
///    mobile deep links), and redeems the hash with
///    `verifyOTP(type: recovery, tokenHash:)` — which needs no stored verifier
///    and emits `AuthChangeEvent.passwordRecovery`, so `AuthGate` shows the
///    reset screen exactly as before.
///
/// ONE handler per app (see `recoveryLinkHandlerProvider`): `AuthGate` can be
/// instantiated twice (`MaterialApp.onUnknownRoute` builds another for OS
/// route pushes), and two handlers would redeem every link twice.
///
/// `recoveryTokenHash` / `classifyAuthLinkError` / `isLinkError` are pure and
/// unit-tested; `RecoveryLinkHandler` takes its side effects by injection so
/// the consume / error paths are testable without an initialised Supabase.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import 'recovery_url_stub.dart'
    if (dart.library.js_interop) 'recovery_url_web.dart';

/// Why a sign-in / reset link could not be turned into a session. Rendered on
/// the login screen (see [authLinkErrorMessage]) instead of hanging on the
/// splash, which is what any error on the auth stream used to do.
enum AuthLinkError {
  /// A PKCE `code` was redeemed on a client that never requested it (the
  /// verifier lives in the client that called `resetPasswordForEmail`).
  wrongDevice,

  /// The token hash / code was already used, or is past its validity window.
  expired,

  /// Anything else (network, malformed link, server error).
  failed,
}

/// The recovery token hash carried by a reset link, or null when the URI is
/// not a recovery link. Accepts the hash in the query (how `reset.html`
/// forwards it) or in the fragment (defensive — Supabase puts implicit-flow
/// tokens there).
String? recoveryTokenHash(Uri uri) {
  final params = <String, String>{...uri.queryParameters};
  if (uri.hasFragment && uri.fragment.isNotEmpty) {
    try {
      for (final e in Uri.splitQueryString(uri.fragment).entries) {
        params.putIfAbsent(e.key, () => e.value);
      }
    } on FormatException {
      // A non-query fragment (e.g. a route) — nothing to merge.
    } on ArgumentError {
      // Malformed percent-encoding; treat as no fragment params.
    }
  }
  if (params['type'] != 'recovery') return null;
  final hash = params['token_hash']?.trim();
  if (hash == null || hash.isEmpty) return null;
  return hash;
}

// GoTrue error codes (gotrue-dart `ErrorCode`) that identify a LINK problem.
// The local SDK throws the verifier error before any request, so it carries
// no code — its constant message is matched instead.
const _kVerifierMessage = 'code verifier';
const _kWrongDeviceCodes = {'bad_code_verifier', 'flow_state_not_found'};
const _kExpiredCodes = {'otp_expired', 'flow_state_expired'};

/// Whether an error from the auth stream is about a sign-in / reset LINK.
/// Session-refresh failures ("Invalid Refresh Token", "Session expired.")
/// also arrive on that stream and must NOT be presented as a link problem.
bool isLinkError(Object error) {
  if (error is! AuthException) return false;
  if (error.message.toLowerCase().contains(_kVerifierMessage)) return true;
  final code = error.code;
  return code != null &&
      (_kWrongDeviceCodes.contains(code) || _kExpiredCodes.contains(code));
}

/// Maps a `verifyOTP` / link-redemption failure to a user-facing category.
/// Only called for errors that ARE about a link (the handler's own failures,
/// or stream errors that pass [isLinkError]).
AuthLinkError classifyAuthLinkError(Object error) {
  if (error is AuthException) {
    if (error.message.toLowerCase().contains(_kVerifierMessage)) {
      return AuthLinkError.wrongDevice;
    }
    final code = error.code;
    if (_kWrongDeviceCodes.contains(code)) return AuthLinkError.wrongDevice;
    if (_kExpiredCodes.contains(code)) return AuthLinkError.expired;
  }
  return AuthLinkError.failed;
}

String authLinkErrorMessage(AppLocalizations l10n, AuthLinkError error) {
  switch (error) {
    case AuthLinkError.wrongDevice:
      return l10n.authLinkWrongDevice;
    case AuthLinkError.expired:
      return l10n.authLinkExpired;
    case AuthLinkError.failed:
      return l10n.authLinkFailed;
  }
}

/// Redeems recovery links from the web initial URL and the mobile deep links.
/// Construct ONCE per app, call [start] (idempotent), [dispose] with the app.
class RecoveryLinkHandler {
  RecoveryLinkHandler({
    required this.verify,
    required this.onStatus,
    this.links,
    this.getInitialLink,
    this.initialWebUri,
    this.isWeb = kIsWeb,
  });

  /// Performs the OTP verification for a token hash; throws on failure.
  final Future<void> Function(String tokenHash) verify;

  /// `null` when a link starts processing (clears a stale notice), an
  /// [AuthLinkError] when redeeming it failed.
  final void Function(AuthLinkError? status) onStatus;

  final bool isWeb;

  /// Test seam for the mobile deep-link stream (defaults to `app_links`).
  final Stream<Uri>? links;

  /// Test seam for the mobile cold-start link (defaults to `app_links`).
  /// Needed because `app_links` replays the initial link only to the FIRST
  /// stream listener — and that is supabase_flutter's own subscription made
  /// inside `Supabase.initialize()`, so this handler never sees it on the
  /// stream.
  final Future<Uri?> Function()? getInitialLink;

  /// Test seam for the web initial URL (defaults to `Uri.base`).
  final Uri? initialWebUri;

  StreamSubscription<Uri>? _sub;
  bool _started = false;
  String? _lastHandled;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (isWeb) {
      // The web app is loaded straight from the link; nothing streams later.
      await handle(initialWebUri ?? Uri.base);
      return;
    }
    final appLinks = (links == null || getInitialLink == null) ? AppLinks() : null;
    final stream = links ?? appLinks!.uriLinkStream;
    _sub = stream.listen(handle, onError: (Object _) {});
    // Cold start from the email: fetch the launch link explicitly (see
    // [getInitialLink]); the dedupe below absorbs the rare double delivery.
    try {
      final initial = await (getInitialLink ?? appLinks!.getInitialLink)();
      if (initial != null) await handle(initial);
    } catch (_) {
      // Platform channel hiccup — a warm deep link will still arrive on the stream.
    }
  }

  /// Returns true when [uri] was a recovery link (consumed, success or not).
  Future<bool> handle(Uri uri) async {
    final hash = recoveryTokenHash(uri);
    if (hash == null) return false;
    final key = uri.toString();
    if (key == _lastHandled) return true; // same link delivered twice
    _lastHandled = key;
    onStatus(null);
    if (isWeb) {
      // Drop the token from the address bar BEFORE the network call: a reload
      // mid-flight must not retry a hash that is about to be consumed.
      clearRecoveryParamsFromAddressBar();
    }
    try {
      await verify(hash);
    } catch (e) {
      onStatus(classifyAuthLinkError(e));
    }
    return true;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
