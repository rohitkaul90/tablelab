import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

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
