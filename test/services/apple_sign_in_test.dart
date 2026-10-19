import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/services/apple_sign_in.dart';

void main() {
  group('generateRawNonce', () {
    test('is 64 lowercase hex chars for the default 32 bytes', () {
      final nonce = generateRawNonce();
      expect(nonce.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(nonce), isTrue);
    });

    test('honours a custom byte length', () {
      expect(generateRawNonce(16).length, 32);
    });

    test('is unique across calls', () {
      final seen = {for (var i = 0; i < 50; i++) generateRawNonce()};
      expect(seen.length, 50);
    });
  });

  group('sha256Hex', () {
    test('matches the known SHA-256 of "abc"', () {
      expect(
        sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('is deterministic and 64 hex chars', () {
      final nonce = generateRawNonce();
      expect(sha256Hex(nonce), sha256Hex(nonce));
      expect(sha256Hex(nonce).length, 64);
    });
  });
}
