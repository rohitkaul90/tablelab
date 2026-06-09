import 'package:flutter/material.dart';

// ── Archetype tags (large toggle buttons) ──────────────────────────────────
const Map<String, String> kArchetypeTags = {
  'fish': 'Fish',
  'nit': 'Nit',
  'tag_player': 'TAG',
  'lag_player': 'LAG',
  'calling_station': 'Calling Station',
  'maniac': 'Maniac',
  'tricky': 'Tricky/GTO',
};

/// Plain-language definition of each archetype — shown in the glossary so
/// players unfamiliar with the jargon understand what each tag means.
const Map<String, String> kArchetypeDefinitions = {
  'fish':
      'Weak, inexperienced player — plays too many hands and makes big fundamental mistakes.',
  'nit':
      'Extremely tight and risk-averse — only plays premium hands and folds to most aggression.',
  'tag_player':
      'Tight-Aggressive: a solid winning style — plays few hands, but bets and raises them hard.',
  'lag_player':
      'Loose-Aggressive: plays many hands with constant pressure; applies heat but can over-bluff.',
  'calling_station':
      'Calls far too often and rarely folds or raises — pays you off, but won\'t fold to bluffs.',
  'maniac':
      'Hyper-aggressive — raises and bluffs relentlessly with a very wide range.',
  'tricky':
      'Strong and balanced — mixes their lines and is hard to read or exploit.',
};

/// Archetypes that share a play-style and can be tagged together (e.g. a player
/// can be both a Fish and a Calling Station). Two archetypes in *different*
/// sets are mutually exclusive — the picker greys out the other.
const List<Set<String>> _archetypeStyles = [
  {'fish', 'calling_station'}, // loose-passive
  {'lag_player', 'maniac'}, // loose-aggressive
  {'nit'}, // tight-passive
  {'tag_player'}, // tight-aggressive
  {'tricky'}, // balanced / strong
];

Set<String> _styleOf(String archetype) {
  for (final s in _archetypeStyles) {
    if (s.contains(archetype)) return s;
  }
  return {archetype};
}

// ── Tendency tags (smaller chips, grouped) ─────────────────────────────────
const Map<String, Map<String, String>> kTendencyGroups = {
  'Preflop': {
    'limps': 'Limps',
    'opens_wide': 'Opens Wide',
    'opens_tight': 'Opens Tight',
    'three_bets_light': '3-Bets Light',
    'four_bets_light': '4-Bets Light',
    'folds_3bet': 'Folds to 3-Bet',
    'calls_3bet_wide': 'Calls 3-Bets Wide',
    'cold_calls': 'Cold Calls',
    'squeezes': 'Squeezes',
    'overfolds_blinds': 'Overfolds Blinds',
  },
  'Postflop': {
    'c_bets_always': 'C-Bets Always',
    'check_folds': 'Check-Folds',
    'folds_to_cbet': 'Folds to C-Bet',
    'barrels_relentless': 'Barrels Turns',
    'gives_up_turn': 'Gives Up Turn',
    'floats_wide': 'Floats Wide',
    'donk_leads': 'Donk-Leads',
    'over_bluffs': 'Over-Bluffs',
    'value_heavy': 'Value-Heavy',
    'overfolds_river': 'Overfolds River',
    'slow_plays': 'Slow-Plays',
    'check_raises': 'Check-Raises',
    'readable_sizing': 'Readable Sizing',
  },
  'Tournament / ICM': {
    'tightens_bubble': 'Tightens at Bubble',
    'shoves_wide_short': 'Shoves Wide (Short)',
    'calls_shoves_light': 'Calls Shoves Light',
  },
};

/// Tendency tags that are mutually exclusive — selecting one greys out the
/// other (they describe opposite tendencies on the same spot). Archetypes are
/// handled separately (single-select) via [tagDisabled].
const Map<String, Set<String>> kContradictions = {
  'opens_wide': {'opens_tight'},
  'opens_tight': {'opens_wide'},
  'folds_3bet': {'calls_3bet_wide'},
  'calls_3bet_wide': {'folds_3bet'},
  'value_heavy': {'over_bluffs'},
  'over_bluffs': {'value_heavy'},
  'barrels_relentless': {'gives_up_turn'},
  'gives_up_turn': {'barrels_relentless'},
  'folds_to_cbet': {'floats_wide'},
  'floats_wide': {'folds_to_cbet'},
};

/// Whether [tag] should be greyed out given the currently [selected] tags:
/// a different archetype is already chosen (one player type at a time), or a
/// contradictory tendency is selected. Selected tags are never disabled.
bool tagDisabled(String tag, Set<String> selected) {
  // Already-selected tags are never disabled — so a legacy read holding a
  // contradictory pair still shows both, and the user can deselect to clean up.
  if (selected.contains(tag)) return false;
  // Archetypes: only a *different* play-style greys this one out. Same-style
  // archetypes (e.g. Fish + Calling Station) can be selected together.
  if (isArchetype(tag)) {
    final style = _styleOf(tag);
    if (selected.any((t) => isArchetype(t) && !style.contains(t))) return true;
  }
  final conflicts = kContradictions[tag];
  if (conflicts != null && selected.any(conflicts.contains)) return true;
  return false;
}

String tagDisplayName(String tag) {
  if (kArchetypeTags.containsKey(tag)) { return kArchetypeTags[tag]!; }
  for (final group in kTendencyGroups.values) {
    if (group.containsKey(tag)) { return group[tag]!; }
  }
  return tag;
}

Color tagColor(String tag) {
  switch (tag) {
    case 'fish':
      return Colors.orange;
    case 'calling_station':
      return Colors.orange.shade700;
    case 'nit':
      return Colors.blueGrey;
    case 'tag_player':
      return Colors.green;
    case 'lag_player':
      return Colors.red;
    case 'maniac':
      return Colors.red.shade900;
    case 'tricky':
      return Colors.purple;
    default:
      return Colors.teal;
  }
}

bool isArchetype(String tag) => kArchetypeTags.containsKey(tag);

/// A version of [tag] with enough contrast to read on its own faint tint in
/// both light and dark themes — keeps the hue but shifts the lightness toward
/// near-black on light backgrounds and toward white on dark ones. Use for any
/// coloured tag/meta chip text so it stays legible regardless of the scaffold.
Color readableTagColor(BuildContext context, Color tag) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Color.lerp(
      tag, isDark ? Colors.white : Colors.black, isDark ? 0.22 : 0.42)!;
}
