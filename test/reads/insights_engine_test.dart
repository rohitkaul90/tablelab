import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/reads/insights_engine.dart';
import 'package:tablelab/reads/tag_definitions.dart';

void main() {
  group('getInsights — coverage', () {
    test('every archetype tag yields at least one insight', () {
      for (final tag in kArchetypeTags.keys) {
        expect(getInsights([tag]), isNotEmpty, reason: 'archetype $tag');
      }
    });

    test('every tendency tag yields at least one insight', () {
      for (final group in kTendencyGroups.values) {
        for (final tag in group.keys) {
          expect(getInsights([tag]), isNotEmpty, reason: 'tendency $tag');
        }
      }
    });

    test('the first insight for a tag carries a basis', () {
      expect(getInsights(['nit']).first.basis, equals('Nit'));
      expect(getInsights(['folds_to_cbet']).first.basis, equals('Folds to C-Bet'));
      expect(getInsights(['tightens_bubble']).first.basis,
          equals('Tightens at Bubble'));
    });

    test('no tags → no insights', () {
      expect(getInsights([]), isEmpty);
    });
  });

  group('getInsights — sound counter-strategy', () {
    bool hasTip(List<String> tags, String needle) =>
        getInsights(tags).any((i) => i.tip.toLowerCase().contains(needle));

    test('a station/fish is never to be bluffed', () {
      expect(hasTip(['calling_station'], "won't fold"), isTrue);
      expect(hasTip(['fish'], 'never bluff'), isTrue);
    });
    test('folds-to-c-bet → c-bet relentlessly', () {
      expect(hasTip(['folds_to_cbet'], 'c-bet relentlessly'), isTrue);
    });
    test('gives-up-turn → float the flop, take the turn', () {
      expect(hasTip(['gives_up_turn'], 'float the flop'), isTrue);
    });
    test('overfolds-blinds → steal relentlessly', () {
      expect(hasTip(['overfolds_blinds'], 'steal relentlessly'), isTrue);
    });
    test('calls-shoves-light → shove tight, stop bluff-shoving', () {
      expect(hasTip(['calls_shoves_light'], 'shove tight'), isTrue);
    });
    test('beefed-up TAG has more than two tips', () {
      expect(getInsights(['tag_player']).length, greaterThan(2));
    });
  });

  group('tagDisabled — contradictions', () {
    test('different play-style archetypes grey each other out', () {
      expect(tagDisabled('nit', {'fish'}), isTrue); // tight-passive vs loose-passive
      expect(tagDisabled('maniac', {'tag_player'}), isTrue);
      expect(tagDisabled('lag_player', {'fish'}), isTrue); // aggressive vs passive
      // the selected archetype itself is never disabled
      expect(tagDisabled('fish', {'fish'}), isFalse);
      // no archetype selected → all available
      expect(tagDisabled('nit', {}), isFalse);
    });

    test('same play-style archetypes can be selected together', () {
      expect(tagDisabled('calling_station', {'fish'}), isFalse); // loose-passive
      expect(tagDisabled('maniac', {'lag_player'}), isFalse); // loose-aggressive
    });

    test('contradictory tendency opposites disable each other', () {
      expect(tagDisabled('opens_tight', {'opens_wide'}), isTrue);
      expect(tagDisabled('floats_wide', {'folds_to_cbet'}), isTrue);
      expect(tagDisabled('over_bluffs', {'value_heavy'}), isTrue);
      expect(tagDisabled('barrels_relentless', {'gives_up_turn'}), isTrue);
      expect(tagDisabled('calls_3bet_wide', {'folds_3bet'}), isTrue);
    });

    test('non-conflicting tendencies stay enabled', () {
      expect(tagDisabled('three_bets_light', {'opens_wide'}), isFalse);
      expect(tagDisabled('limps', {'fish'}), isFalse); // tendency vs archetype
      expect(tagDisabled('squeezes', {'overfolds_blinds'}), isFalse);
    });
  });

  group('tag_definitions helpers', () {
    test('tagDisplayName resolves new tags', () {
      expect(tagDisplayName('barrels_relentless'), equals('Barrels Turns'));
      expect(tagDisplayName('shoves_wide_short'), equals('Shoves Wide (Short)'));
      expect(tagDisplayName('unknown_tag'), equals('unknown_tag'));
    });
    test('isArchetype distinguishes archetypes from tendencies', () {
      expect(isArchetype('nit'), isTrue);
      expect(isArchetype('limps'), isFalse);
    });
  });
}
