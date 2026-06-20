import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/services/ai_service.dart';

void main() {
  group('AiUsage.fromRows', () {
    test('empty rows → zero counts', () {
      final u = AiUsage.fromRows(const [], exempt: false);
      expect(u.session, 0);
      expect(u.hand, 0);
      expect(u.exempt, isFalse);
    });

    test('counts session and hand analyses by function_name', () {
      final rows = <Map<String, dynamic>>[
        {'function_name': 'analyze-session'},
        {'function_name': 'analyze-hand'},
        {'function_name': 'analyze-hand'},
        {'function_name': 'analyze-session'},
        {'function_name': 'analyze-hand'},
      ];
      final u = AiUsage.fromRows(rows, exempt: false);
      expect(u.session, 2);
      expect(u.hand, 3);
    });

    test('ignores unknown / null function names', () {
      final rows = <Map<String, dynamic>>[
        {'function_name': 'analyze-session'},
        {'function_name': 'scrape-tournaments'},
        {'function_name': null},
        {'other': 'x'},
      ];
      final u = AiUsage.fromRows(rows, exempt: false);
      expect(u.session, 1);
      expect(u.hand, 0);
    });

    test('passes through the exempt flag', () {
      expect(AiUsage.fromRows(const [], exempt: true).exempt, isTrue);
      expect(AiUsage.fromRows(const [], exempt: false).exempt, isFalse);
    });
  });

  group('AiException.fromResponse', () {
    test('429 with server message → rate-limited, uses server text', () {
      final e = AiException.fromResponse(
        429,
        {'error': 'Daily analysis limit reached. Please try again tomorrow.'},
      );
      expect(e.status, 429);
      expect(e.isRateLimited, isTrue);
      expect(e.isAtCapacity, isFalse);
      expect(e.message, contains('Daily analysis limit'));
    });

    test('503 with server message → at-capacity, uses server text', () {
      final e = AiException.fromResponse(
        503,
        {'error': 'AI coaching is temporarily at capacity. Please try again later.'},
      );
      expect(e.status, 503);
      expect(e.isAtCapacity, isTrue);
      expect(e.isRateLimited, isFalse);
      expect(e.message, contains('at capacity'));
    });

    test('429 with no usable details → falls back to the limit message', () {
      final e = AiException.fromResponse(429, null);
      expect(e.isRateLimited, isTrue);
      expect(e.message, contains('tomorrow'));
    });

    test('503 with non-map details → falls back to the capacity message', () {
      final e = AiException.fromResponse(503, 'oops');
      expect(e.isAtCapacity, isTrue);
      expect(e.message, contains('later'));
    });

    test('500 → generic fallback, neither flag set', () {
      final e = AiException.fromResponse(500, null);
      expect(e.isRateLimited, isFalse);
      expect(e.isAtCapacity, isFalse);
      expect(e.message, 'Analysis failed. Please try again.');
    });
  });
}
