import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

// ── Archetype tags (large toggle buttons) ──────────────────────────────────
// Ids are persisted in `player_reads.tags` and sent to the AI as-is — never
// rename. Display text lives in the ARB files (`tagDisplayName`).
const List<String> kArchetypeTags = [
  'fish',
  'nit',
  'tag_player',
  'lag_player',
  'calling_station',
  'maniac',
  'tricky',
];

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
/// A labelled group of tendency tag ids. [id] is stable; the header text comes
/// from `tendencyGroupLabel`.
class TendencyGroup {
  final String id;
  final List<String> tagIds;
  const TendencyGroup(this.id, this.tagIds);
}

const List<TendencyGroup> kTendencyGroups = [
  TendencyGroup('preflop', ['limps', 'opens_wide', 'opens_tight', 'three_bets_light', 'four_bets_light', 'folds_3bet', 'calls_3bet_wide', 'cold_calls', 'squeezes', 'overfolds_blinds']),
  TendencyGroup('postflop', ['c_bets_always', 'check_folds', 'folds_to_cbet', 'barrels_relentless', 'gives_up_turn', 'floats_wide', 'donk_leads', 'over_bluffs', 'value_heavy', 'overfolds_river', 'slow_plays', 'check_raises', 'readable_sizing']),
  TendencyGroup('tournament_icm', ['tightens_bubble', 'shoves_wide_short', 'calls_shoves_light']),
];

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

/// Localized label for a tag id; unknown (legacy / future) ids show raw.
String tagDisplayName(AppLocalizations l10n, String tag) => switch (tag) {
      'fish' => l10n.tagFish,
      'nit' => l10n.tagNit,
      'tag_player' => l10n.tagTagPlayer,
      'lag_player' => l10n.tagLagPlayer,
      'calling_station' => l10n.tagCallingStation,
      'maniac' => l10n.tagManiac,
      'tricky' => l10n.tagTricky,
      'limps' => l10n.tagLimps,
      'opens_wide' => l10n.tagOpensWide,
      'opens_tight' => l10n.tagOpensTight,
      'three_bets_light' => l10n.tagThreeBetsLight,
      'four_bets_light' => l10n.tagFourBetsLight,
      'folds_3bet' => l10n.tagFolds3bet,
      'calls_3bet_wide' => l10n.tagCalls3betWide,
      'cold_calls' => l10n.tagColdCalls,
      'squeezes' => l10n.tagSqueezes,
      'overfolds_blinds' => l10n.tagOverfoldsBlinds,
      'c_bets_always' => l10n.tagCBetsAlways,
      'check_folds' => l10n.tagCheckFolds,
      'folds_to_cbet' => l10n.tagFoldsToCbet,
      'barrels_relentless' => l10n.tagBarrelsRelentless,
      'gives_up_turn' => l10n.tagGivesUpTurn,
      'floats_wide' => l10n.tagFloatsWide,
      'donk_leads' => l10n.tagDonkLeads,
      'over_bluffs' => l10n.tagOverBluffs,
      'value_heavy' => l10n.tagValueHeavy,
      'overfolds_river' => l10n.tagOverfoldsRiver,
      'slow_plays' => l10n.tagSlowPlays,
      'check_raises' => l10n.tagCheckRaises,
      'readable_sizing' => l10n.tagReadableSizing,
      'tightens_bubble' => l10n.tagTightensBubble,
      'shoves_wide_short' => l10n.tagShovesWideShort,
      'calls_shoves_light' => l10n.tagCallsShovesLight,
      _ => tag,
    };

/// Plain-language definition of an archetype id (glossary); '' if unknown.
String archetypeDefinition(AppLocalizations l10n, String id) => switch (id) {
      'fish' => l10n.archetypeDefFish,
      'nit' => l10n.archetypeDefNit,
      'tag_player' => l10n.archetypeDefTagPlayer,
      'lag_player' => l10n.archetypeDefLagPlayer,
      'calling_station' => l10n.archetypeDefCallingStation,
      'maniac' => l10n.archetypeDefManiac,
      'tricky' => l10n.archetypeDefTricky,
      _ => '',
    };

/// Section header for a [TendencyGroup.id].
String tendencyGroupLabel(AppLocalizations l10n, String id) => switch (id) {
      'preflop' => l10n.tagGroupPreflop,
      'postflop' => l10n.tagGroupPostflop,
      'tournament_icm' => l10n.tagGroupTournamentIcm,
      _ => id,
    };

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

bool isArchetype(String tag) => kArchetypeTags.contains(tag);

/// A version of [tag] with enough contrast to read on its own faint tint in
/// both light and dark themes — keeps the hue but shifts the lightness toward
/// near-black on light backgrounds and toward white on dark ones. Use for any
/// coloured tag/meta chip text so it stays legible regardless of the scaffold.
Color readableTagColor(BuildContext context, Color tag) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Color.lerp(
      tag, isDark ? Colors.white : Colors.black, isDark ? 0.22 : 0.42)!;
}
