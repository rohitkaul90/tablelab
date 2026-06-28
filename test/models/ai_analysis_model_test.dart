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

  group('malformed model output is parsed defensively (no crash)', () {
    // The real shape that crashed the analysis screen in prod: Claude botched
    // the tool call — each street came back as a STRING containing the literal
    // `<parameter name="decision">…` tag, and optimal/rationale/wasGto were
    // flattened to the top level. A strict `as Map` cast threw; the salvageable
    // top-level fields must still render.
    test('streets returned as strings drop to null, top-level fields survive',
        () {
      final a = HandCoachingAnalysis.fromJson(const {
        'summary': 'JQo BTN open vs BB call, river bluff',
        'verdict': 'leakDetected',
        'keyMistake': 'Fired a pot-sized river bluff with no fold equity.',
        'facts': ['[FACT - x]'],
        'preflop': '\n<parameter name="decision">Raised to 35 from BTN',
        'flop': '\n<parameter name="decision">Bet 30 into 75',
        'turn': '\n<parameter name="decision">Bet 100 into 135',
        'river': '\n<parameter name="decision">Bet 335 into 335',
        'wasGto': false, // flattened to top level — ignored, doesn't crash
        'optimal': 'Check back and give up',
      });
      expect(a.preflop, isNull);
      expect(a.flop, isNull);
      expect(a.turn, isNull);
      expect(a.river, isNull);
      expect(a.summary, 'JQo BTN open vs BB call, river bluff');
      expect(a.verdict, 'leakDetected');
      expect(a.keyMistake, isNotNull);
      expect(a.facts, hasLength(1));
    });

    test('non-bool wasGto and non-string scalars degrade, not crash', () {
      final f = StreetFeedback.fromJson(const {
        'decision': 'called',
        'optimal': 42, // wrong type
        'rationale': null,
        'wasGto': 'true', // string, not bool
        'confidence': 7, // wrong type
      });
      expect(f.optimal, ''); // non-string → default
      expect(f.wasGto, isTrue); // non-bool → default true
      expect(f.confidence, isNull); // non-string → null
    });

    test('facts containing a non-string element filters it out', () {
      final a = HandCoachingAnalysis.fromJson(const {
        'summary': 's',
        'facts': ['[FACT - a]', 99, '[FACT - b]'],
      });
      expect(a.facts, ['[FACT - a]', '[FACT - b]']);
    });

    test('a fully-malformed (empty) response reports isEmpty', () {
      final a = HandCoachingAnalysis.fromJson(const {
        'flop': '<parameter name="decision">x',
        'turn': '<parameter name="decision">y',
      });
      expect(a.isEmpty, isTrue);
    });

    test('a real analysis is NOT isEmpty', () {
      final a = HandCoachingAnalysis.fromJson(const {
        'summary': 'good summary',
        'flop': {'decision': 'bet', 'optimal': 'bet', 'rationale': 'r', 'wasGto': true},
      });
      expect(a.isEmpty, isFalse);
      expect(a.flop, isNotNull);
    });
  });
}
