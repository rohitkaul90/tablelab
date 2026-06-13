import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/ai_analysis_model.dart';

void main() {
  group('StreetFeedback trust-pack fields', () {
    test('parses confidence and alternative when present', () {
      final f = StreetFeedback.fromJson(const {
        'decision': 'called',
        'optimal': 'raise',
        'rationale': 'because',
        'wasGto': false,
        'confidence': 'high',
        'alternative': 'A small raise is also defensible.',
      });
      expect(f.confidence, 'high');
      expect(f.alternative, 'A small raise is also defensible.');
    });

    test('legacy cached analyses without the fields parse as null', () {
      final f = StreetFeedback.fromJson(const {
        'decision': 'called',
        'optimal': 'raise',
        'rationale': 'because',
        'wasGto': true,
      });
      expect(f.confidence, isNull);
      expect(f.alternative, isNull);
    });
  });

  group('HandCoachingAnalysis facts', () {
    test('parses the facts list when present', () {
      final a = HandCoachingAnalysis.fromJson(const {
        'summary': 'AKo 3-bet pot',
        'verdict': 'neutral',
        'keyMistake': null,
        'facts': ['[FACT — hole cards: As Kd]', '[FACT — flush status: none]'],
      });
      expect(a.facts, hasLength(2));
      expect(a.facts.first, startsWith('[FACT'));
    });

    test('legacy cached analyses parse with an empty facts list', () {
      final a = HandCoachingAnalysis.fromJson(const {
        'summary': 'AKo 3-bet pot',
        'verdict': 'highEV',
        'keyMistake': null,
      });
      expect(a.facts, isEmpty);
    });
  });
}
