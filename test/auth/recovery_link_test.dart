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

  group('classifyAuthLinkError', () {
    test('missing PKCE verifier → wrongDevice', () {
      expect(
        classifyAuthLinkError(const AuthException(
            'Code verifier could not be found in local storage.')),
        AuthLinkError.wrongDevice,
      );
    });

    test('expired / invalid / 403 → expired', () {
      expect(
        classifyAuthLinkError(const AuthException(
            'Email link is invalid or has expired',
            statusCode: '403')),
        AuthLinkError.expired,
      );
      expect(
        classifyAuthLinkError(
            const AuthException('Token has expired', statusCode: '401')),
        AuthLinkError.expired,
      );
    });

    test('anything else → failed', () {
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
        verify: (h) async => verified.add(h),
        onStatus: statuses.add,
      );
      await handler.start();
      links.add(Uri.parse('io.supabase.pokertracker://login-callback/?code=x'));
      links.add(Uri.parse(
          'io.supabase.pokertracker://reset-password?token_hash=m1&type=recovery'));
      await Future<void>.delayed(Duration.zero);
      expect(verified, ['m1']);
      expect(statuses, [null]);
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
            statusCode: '403'),
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
