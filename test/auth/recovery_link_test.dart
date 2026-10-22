import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tablelab/auth/recovery_link.dart';
import 'package:tablelab/l10n/generated/app_localizations.dart';

void main() {
  group('recoveryTokenHash', () {
    test('reads token_hash + type=recovery from the query', () {
      final uri = Uri.parse(
          'https://tablelab.app/?token_hash=pkce_abc123&type=recovery');
      expect(recoveryTokenHash(uri), 'pkce_abc123');
    });

    test('reads them from a deep link regardless of scheme/host', () {
      final uri = Uri.parse(
          'io.supabase.pokertracker://reset-password?token_hash=h1&type=recovery');
      expect(recoveryTokenHash(uri), 'h1');
    });

    test('accepts the params in the fragment', () {
      final uri =
          Uri.parse('https://tablelab.app/#token_hash=h2&type=recovery');
      expect(recoveryTokenHash(uri), 'h2');
    });

    test('ignores other link types and PKCE codes', () {
      expect(
        recoveryTokenHash(
            Uri.parse('https://tablelab.app/?token_hash=h&type=signup')),
        isNull,
      );
      expect(
        recoveryTokenHash(Uri.parse('https://tablelab.app/?code=abc')),
        isNull,
      );
      expect(recoveryTokenHash(Uri.parse('https://tablelab.app/')), isNull);
    });

    test('rejects an empty hash and tolerates a non-query fragment', () {
      expect(
        recoveryTokenHash(
            Uri.parse('https://tablelab.app/?token_hash=&type=recovery')),
        isNull,
      );
      expect(
        recoveryTokenHash(Uri.parse('https://tablelab.app/#/some/route')),
        isNull,
      );
    });
  });

  group('isLinkError / classifyAuthLinkError', () {
    const verifier =
        AuthException('Code verifier could not be found in local storage.');
    const otpExpired = AuthException('Email link is invalid or has expired',
        statusCode: '403', code: 'otp_expired');
    const flowExpired = AuthException('PKCE flow state expired',
        statusCode: '403', code: 'flow_state_expired');
    const badVerifier = AuthException('invalid code verifier',
        statusCode: '400', code: 'bad_code_verifier');
    // Session-refresh failures also travel the auth stream — never a link.
    const refreshToken = AuthException('Invalid Refresh Token: Already Used',
        statusCode: '400', code: 'refresh_token_already_used');
    const sessionExpired = AuthException('Session expired.');
    const clockSkew =
        AuthException('invalid claim: token is expired', statusCode: '401');

    test('link errors are recognised by SDK message or GoTrue code', () {
      expect(isLinkError(verifier), isTrue);
      expect(isLinkError(otpExpired), isTrue);
      expect(isLinkError(flowExpired), isTrue);
      expect(isLinkError(badVerifier), isTrue);
    });

    test('refresh / session / skew / non-auth errors are NOT link errors', () {
      expect(isLinkError(refreshToken), isFalse);
      expect(isLinkError(sessionExpired), isFalse);
      expect(isLinkError(clockSkew), isFalse);
      expect(isLinkError(StateError('x')), isFalse);
    });

    test('missing / wrong verifier → wrongDevice', () {
      expect(classifyAuthLinkError(verifier), AuthLinkError.wrongDevice);
      expect(classifyAuthLinkError(badVerifier), AuthLinkError.wrongDevice);
    });

    test('otp / flow expiry → expired', () {
      expect(classifyAuthLinkError(otpExpired), AuthLinkError.expired);
      expect(classifyAuthLinkError(flowExpired), AuthLinkError.expired);
    });

    test('free-text "invalid"/"expired" without a code is NOT expired', () {
      // Substring matching misclassified unrelated errors (review finding).
      expect(classifyAuthLinkError(clockSkew), AuthLinkError.failed);
      expect(classifyAuthLinkError(const AuthException('boom')),
          AuthLinkError.failed);
      expect(classifyAuthLinkError(StateError('x')), AuthLinkError.failed);
    });
  });

  group('authLinkErrorMessage', () {
    test('every error has a non-empty localized message', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      for (final e in AuthLinkError.values) {
        expect(authLinkErrorMessage(l10n, e), isNotEmpty);
      }
    });
  });

  group('RecoveryLinkHandler', () {
    Uri recovery(String hash) => Uri.parse(
        'io.supabase.pokertracker://reset-password?token_hash=$hash&type=recovery');

    test('web: redeems the initial URL hash and clears a stale notice', () async {
      final verified = <String>[];
      final statuses = <AuthLinkError?>[];
      final handler = RecoveryLinkHandler(
        isWeb: true,
        initialWebUri:
            Uri.parse('https://tablelab.app/?token_hash=h9&type=recovery'),
        verify: (h) async => verified.add(h),
        onStatus: statuses.add,
      );
      await handler.start();
      expect(verified, ['h9']);
      // `null` = a link started processing (clears any old notice); no error.
      expect(statuses, [null]);
    });

    test('web: a plain app URL is not a recovery link', () async {
      var calls = 0;
      final handler = RecoveryLinkHandler(
        isWeb: true,
        initialWebUri: Uri.parse('https://tablelab.app/'),
        verify: (_) async => calls++,
        onStatus: (_) => fail('no status expected'),
      );
      await handler.start();
      expect(calls, 0);
    });

    test('mobile: consumes recovery deep links from the stream only', () async {
      final links = StreamController<Uri>();
      final verified = <String>[];
      final statuses = <AuthLinkError?>[];
      final handler = RecoveryLinkHandler(
        isWeb: false,
        links: links.stream,
        getInitialLink: () async => null,
        verify: (h) async => verified.add(h),
        onStatus: statuses.add,
      );
      await handler.start();
      links.add(Uri.parse('io.supabase.pokertracker://login-callback/?code=x'));
      links.add(recovery('m1'));
      await Future<void>.delayed(Duration.zero);
      expect(verified, ['m1']);
      expect(statuses, [null]);
      handler.dispose();
      await links.close();
    });

    test('mobile: the cold-start link is fetched explicitly (app_links only '
        'replays it to the FIRST stream listener, which is the SDK)', () async {
      final links = StreamController<Uri>();
      final verified = <String>[];
      final handler = RecoveryLinkHandler(
        isWeb: false,
        links: links.stream,
        getInitialLink: () async => recovery('cold'),
        verify: (h) async => verified.add(h),
        onStatus: (_) {},
      );
      await handler.start();
      expect(verified, ['cold']);
      handler.dispose();
      await links.close();
    });

    test('mobile: the same link delivered twice is redeemed once', () async {
      final links = StreamController<Uri>();
      final verified = <String>[];
      final handler = RecoveryLinkHandler(
        isWeb: false,
        links: links.stream,
        getInitialLink: () async => recovery('dup'),
        verify: (h) async => verified.add(h),
        onStatus: (_) {},
      );
      await handler.start();
      links.add(recovery('dup')); // the stream replays the launch link too
      links.add(recovery('next')); // a genuinely new link still works
      await Future<void>.delayed(Duration.zero);
      expect(verified, ['dup', 'next']);
      handler.dispose();
      await links.close();
    });

    test('a failed verification reports the classified error', () async {
      final statuses = <AuthLinkError?>[];
      final handler = RecoveryLinkHandler(
        isWeb: true,
        initialWebUri:
            Uri.parse('https://tablelab.app/?token_hash=old&type=recovery'),
        verify: (_) async => throw const AuthException(
            'Email link is invalid or has expired',
            statusCode: '403',
            code: 'otp_expired'),
        onStatus: statuses.add,
      );
      await handler.start();
      expect(statuses, [null, AuthLinkError.expired]);
    });

    test('start() is idempotent', () async {
      var calls = 0;
      final handler = RecoveryLinkHandler(
        isWeb: true,
        initialWebUri:
            Uri.parse('https://tablelab.app/?token_hash=h&type=recovery'),
        verify: (_) async => calls++,
        onStatus: (_) {},
      );
      await handler.start();
      await handler.start();
      expect(calls, 1);
    });
  });
}
