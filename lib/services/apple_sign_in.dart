import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hands Apple's one-shot `authorizationCode` to the `apple-link` Edge
/// Function, which exchanges it for a refresh token and stores it server-side
/// so `delete-account` can revoke it (App Store Review Guideline 5.1.1(v)).
///
/// Best-effort by design: the code expires in ~5 minutes and is single-use, so
/// this must run right after `signInWithIdToken` (the session's JWT is what
/// authorizes the call), but a failure (function not yet deployed, offline,
/// secrets unset) must never block sign-in — the server alerts on its side.
Future<void> linkAppleAuthorization(
  SupabaseClient client,
  String authorizationCode,
) async {
  try {
    await client.functions.invoke(
      'apple-link',
      body: {'authorizationCode': authorizationCode},
    );
  } catch (e) {
    debugPrint('apple-link failed (sign-in unaffected): $e');
  }
}

/// Nonce helpers for the native Sign in with Apple → Supabase flow.
///
/// Apple signs the SHA-256 of a nonce into the identity token; Supabase then
/// verifies the token against the RAW nonce. So the caller generates
/// [generateRawNonce] once, passes [sha256Hex] of it to
/// `SignInWithApple.getAppleIDCredential(nonce:)`, and the raw value to
/// `auth.signInWithIdToken(nonce:)`. (gotrue 2.20 has no `generateRawNonce`
/// despite the supabase_flutter README — this is the local equivalent.)
///
/// Pure Dart, no platform calls, so it is unit-testable on any host.
String generateRawNonce([int byteLength = 32]) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Lowercase hex SHA-256 of [input] (UTF-8).
String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

/// Apple's `givenName`/`familyName` → one display name, or null when Apple
/// sent nothing (every authorization after the first, or the user cleared it).
String? appleDisplayName(String? givenName, String? familyName) {
  final parts = [givenName, familyName]
      .map((p) => p?.trim() ?? '')
      .where((p) => p.isNotEmpty);
  final joined = parts.join(' ');
  return joined.isEmpty ? null : joined;
}
