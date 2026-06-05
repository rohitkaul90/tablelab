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
}
