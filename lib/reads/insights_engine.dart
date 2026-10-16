import '../l10n/generated/app_localizations.dart';

/// A strategy tip for an opponent read. [basisTags] are the TAG IDS the tip
/// is derived from (empty = a follow-up to the previous tip); the UI renders
/// them via `tagDisplayName`.
class ReadInsight {
  final String tip;
  final List<String> basisTags;
  const ReadInsight(this.tip, {this.basisTags = const []});
}

/// Rule-based coaching for a set of tag ids, worded in [l10n]'s language.
List<ReadInsight> getInsights(List<String> tags, AppLocalizations l10n) {
  final s = tags.toSet();
  final insights = <ReadInsight>[];

  // ── Archetypes ──────────────────────────────────────────────────────────
  if (s.contains('fish') || s.contains('calling_station')) {
    final basisTags = [s.contains('calling_station') ? 'calling_station' : 'fish'];
    insights.add(ReadInsight(l10n.insightValueBetWideThin, basisTags: basisTags));
    insights.add(ReadInsight(l10n.insightNeverBluffWonT));
    if (s.contains('limps')) {
      insights.add(ReadInsight(l10n.insightIsolateLimpsWideRaising, basisTags: ['fish', 'limps']));
    }
  }

  if (s.contains('nit')) {
    insights.add(ReadInsight(l10n.insightGiveFullCreditLarge, basisTags: ['nit']));
    insights.add(ReadInsight(l10n.insightAttackLight3Bets));
    insights.add(ReadInsight(l10n.insightFoldContinuationBetsWet));
  }

  if (s.contains('lag_player')) {
    insights.add(ReadInsight(l10n.insightCallDownLighterThan, basisTags: ['lag_player']));
    insights.add(ReadInsight(l10n.insightCheckRaiseAsTrap));
    insights.add(ReadInsight(l10n.insightWiden3BetCalling));
    insights.add(ReadInsight(l10n.insightDonTBloatPots));
  }

  if (s.contains('tag_player')) {
    insights.add(ReadInsight(l10n.insightRespectBetsHaveRange, basisTags: ['tag_player']));
    insights.add(ReadInsight(l10n.insight3BetAsSteal));
    insights.add(ReadInsight(l10n.insightDonTPayOff));
    insights.add(ReadInsight(l10n.insightApplyPositionalPressureFloat));
  }

  if (s.contains('maniac')) {
    insights.add(ReadInsight(l10n.insightTrapStrongHandsLet, basisTags: ['maniac']));
    insights.add(ReadInsight(l10n.insightDonTSemiBluff));
    insights.add(ReadInsight(l10n.insightCallDownAnyPair));
  }

  if (s.contains('tricky')) {
    insights.add(ReadInsight(l10n.insightDonTBetFold, basisTags: ['tricky']));
    insights.add(ReadInsight(l10n.insightMixUpOwnLines));
  }

  // ── Preflop tendencies ──────────────────────────────────────────────────
  if (s.contains('opens_wide')) {
    insights.add(ReadInsight(l10n.insight3BetSqueezeOpens, basisTags: ['opens_wide']));
  }
  if (s.contains('opens_tight')) {
    insights.add(ReadInsight(l10n.insightFoldRaisesUnlessYou, basisTags: ['opens_tight']));
  }
  if (s.contains('limps') && !s.contains('fish') && !s.contains('calling_station')) {
    insights.add(ReadInsight(l10n.insightIsolateLimps34, basisTags: ['limps']));
  }
  if (s.contains('three_bets_light')) {
    insights.add(ReadInsight(l10n.insight4BetLightFor, basisTags: ['three_bets_light']));
  }
  if (s.contains('four_bets_light')) {
    insights.add(ReadInsight(l10n.insightFlatStrong3Bets, basisTags: ['four_bets_light']));
  }
  if (s.contains('folds_3bet')) {
    insights.add(ReadInsight(l10n.insight3BetThemLiberally, basisTags: ['folds_3bet']));
  }
  if (s.contains('calls_3bet_wide')) {
    insights.add(ReadInsight(l10n.insight3BetForValue, basisTags: ['calls_3bet_wide']));
  }
  if (s.contains('cold_calls')) {
    insights.add(ReadInsight(l10n.insightSqueezeWhenColdCall, basisTags: ['cold_calls']));
  }
  if (s.contains('squeezes')) {
    insights.add(ReadInsight(l10n.insightTightenColdCallsFront, basisTags: ['squeezes']));
  }
  if (s.contains('overfolds_blinds')) {
    insights.add(ReadInsight(l10n.insightStealRelentlesslyFromCo, basisTags: ['overfolds_blinds']));
  }

  // ── Postflop tendencies ─────────────────────────────────────────────────
  if (s.contains('c_bets_always')) {
    insights.add(ReadInsight(l10n.insightCheckRaiseCBets, basisTags: ['c_bets_always']));
    insights.add(ReadInsight(l10n.insightFloatPositionTakePot));
  }
  if (s.contains('check_folds')) {
    insights.add(ReadInsight(l10n.insightBetWhenCheckGive, basisTags: ['check_folds']));
  }
  if (s.contains('folds_to_cbet')) {
    insights.add(ReadInsight(l10n.insightCBetRelentlesslySmall, basisTags: ['folds_to_cbet']));
  }
  if (s.contains('barrels_relentless')) {
    insights.add(ReadInsight(l10n.insightBluffCatchLighterDon, basisTags: ['barrels_relentless']));
  }
  if (s.contains('gives_up_turn')) {
    insights.add(ReadInsight(l10n.insightFloatFlopPositionTake, basisTags: ['gives_up_turn']));
  }
  if (s.contains('floats_wide')) {
    insights.add(ReadInsight(l10n.insightBarrelTurnRiverFor, basisTags: ['floats_wide']));
  }
  if (s.contains('donk_leads')) {
    insights.add(ReadInsight(l10n.insightLeadsAreUsuallyWeak, basisTags: ['donk_leads']));
  }
  if (s.contains('over_bluffs')) {
    insights.add(ReadInsight(l10n.insightCallRiversLighterOver, basisTags: ['over_bluffs']));
  }
  if (s.contains('value_heavy')) {
    insights.add(ReadInsight(l10n.insightFoldLargeBetsUnless, basisTags: ['value_heavy']));
    insights.add(ReadInsight(l10n.insightBluffThemBoardsWhere));
  }
  if (s.contains('overfolds_river')) {
    insights.add(ReadInsight(l10n.insightTripleBarrelBluffRivers, basisTags: ['overfolds_river']));
  }
  if (s.contains('slow_plays')) {
    insights.add(ReadInsight(l10n.insightBeCautiousWhenCheck, basisTags: ['slow_plays']));
  }
  if (s.contains('check_raises')) {
    insights.add(ReadInsight(l10n.insightBetSmallerBoardsWhere, basisTags: ['check_raises']));
  }
  if (s.contains('readable_sizing')) {
    insights.add(ReadInsight(l10n.insightUseBetSizingAs, basisTags: ['readable_sizing']));
  }

  // ── Tournament / ICM tendencies ─────────────────────────────────────────
  if (s.contains('tightens_bubble')) {
    insights.add(ReadInsight(l10n.insightPilePressureNearBubble, basisTags: ['tightens_bubble']));
  }
  if (s.contains('shoves_wide_short')) {
    insights.add(ReadInsight(l10n.insightCallShortStackShoves, basisTags: ['shoves_wide_short']));
  }
  if (s.contains('calls_shoves_light')) {
    insights.add(ReadInsight(l10n.insightShoveTightForValue, basisTags: ['calls_shoves_light']));
  }

  return insights;
}
