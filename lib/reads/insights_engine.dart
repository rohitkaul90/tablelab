class ReadInsight {
  final String tip;
  final String? basis;
  const ReadInsight(this.tip, {this.basis});
}

List<ReadInsight> getInsights(List<String> tags) {
  final s = tags.toSet();
  final insights = <ReadInsight>[];

  // ── Archetypes ──────────────────────────────────────────────────────────
  if (s.contains('fish') || s.contains('calling_station')) {
    final basis = s.contains('calling_station') ? 'Calling Station' : 'Fish';
    insights.add(ReadInsight('Value bet wide and thin to the river — they call too much.', basis: basis));
    insights.add(ReadInsight('Never bluff — they won\'t fold.'));
    if (s.contains('limps')) {
      insights.add(ReadInsight('Isolate their limps with a wide raising range.', basis: 'Fish + Limps'));
    }
  }

  if (s.contains('nit')) {
    insights.add(ReadInsight('Give full credit to large bets — their range is extremely strong.', basis: 'Nit'));
    insights.add(ReadInsight('Attack with light 3-bets and steal attempts; they fold the bottom of their range.'));
    insights.add(ReadInsight('Fold to their continuation bets on wet boards unless you have a strong hand or draw.'));
  }

  if (s.contains('lag_player')) {
    insights.add(ReadInsight('Call down lighter than normal — they over-bluff.', basis: 'LAG'));
    insights.add(ReadInsight('Check-raise as a trap; they c-bet too frequently.'));
    insights.add(ReadInsight('Widen your 3-bet calling range vs. their opens.'));
    insights.add(ReadInsight('Don\'t bloat pots out of position with marginal hands — keep the pot small or play back in position.'));
  }

  if (s.contains('tag_player')) {
    insights.add(ReadInsight('Respect their bets — they have range discipline.', basis: 'TAG'));
    insights.add(ReadInsight('3-bet as a steal from late position; they fold the bottom of their range.'));
    insights.add(ReadInsight('Don\'t pay off their river bets — bluff-catch tighter; when they fire, they have it.'));
    insights.add(ReadInsight('Apply positional pressure — float and barrel when they c-bet and then give up.'));
  }

  if (s.contains('maniac')) {
    insights.add(ReadInsight('Trap with strong hands — let them build the pot.', basis: 'Maniac'));
    insights.add(ReadInsight('Don\'t semi-bluff; let them hang themselves with their aggression.'));
    insights.add(ReadInsight('Call down with any pair or decent draw — they over-represent constantly.'));
  }

  if (s.contains('tricky')) {
    insights.add(ReadInsight('Don\'t bet-fold marginal hands — they exploit overfolding.', basis: 'Tricky/GTO'));
    insights.add(ReadInsight('Mix up your own lines; they will find and exploit any pattern.'));
  }

  // ── Preflop tendencies ──────────────────────────────────────────────────
  if (s.contains('opens_wide')) {
    insights.add(ReadInsight('3-bet and squeeze vs. their opens — their range is weak.', basis: 'Opens Wide'));
  }
  if (s.contains('opens_tight')) {
    insights.add(ReadInsight('Fold to their raises unless you have a premium hand.', basis: 'Opens Tight'));
  }
  if (s.contains('limps') && !s.contains('fish') && !s.contains('calling_station')) {
    insights.add(ReadInsight('Isolate their limps with a 3–4× raise.', basis: 'Limps'));
  }
  if (s.contains('three_bets_light')) {
    insights.add(ReadInsight('4-bet light for value; widen your flatting range vs. their 3-bets.', basis: '3-Bets Light'));
  }
  if (s.contains('four_bets_light')) {
    insights.add(ReadInsight('Flat your strong 3-bets in position and let them barrel; 5-bet only premiums. Call their 4-bet a touch wider with hands that flop well.', basis: '4-Bets Light'));
  }
  if (s.contains('folds_3bet')) {
    insights.add(ReadInsight('3-bet them liberally as a steal from BTN and CO.', basis: 'Folds to 3-Bet'));
  }
  if (s.contains('calls_3bet_wide')) {
    insights.add(ReadInsight('3-bet for value only (and size up) — don\'t 3-bet bluff. Then barrel postflop; they peel too wide.', basis: 'Calls 3-Bets Wide'));
  }
  if (s.contains('cold_calls')) {
    insights.add(ReadInsight('Squeeze when they cold-call behind — they will often fold.', basis: 'Cold Calls'));
  }
  if (s.contains('squeezes')) {
    insights.add(ReadInsight('Tighten your cold-calls in front of them, and flat your premiums to trap the squeeze.', basis: 'Squeezes'));
  }
  if (s.contains('overfolds_blinds')) {
    insights.add(ReadInsight('Steal relentlessly from the CO/BTN/SB — they surrender their blinds too cheaply.', basis: 'Overfolds Blinds'));
  }

  // ── Postflop tendencies ─────────────────────────────────────────────────
  if (s.contains('c_bets_always')) {
    insights.add(ReadInsight('Check-raise their c-bets more freely — they bet too mechanically.', basis: 'C-Bets Always'));
    insights.add(ReadInsight('Float in position and take the pot away on the turn.'));
  }
  if (s.contains('check_folds')) {
    insights.add(ReadInsight('Bet when they check — they give up with little fight.', basis: 'Check-Folds'));
  }
  if (s.contains('folds_to_cbet')) {
    insights.add(ReadInsight('C-bet relentlessly with a small size — they fold far too often to the first barrel.', basis: 'Folds to C-Bet'));
  }
  if (s.contains('barrels_relentless')) {
    insights.add(ReadInsight('Bluff-catch lighter, and don\'t fold the flop planning to fold the turn — they keep firing without the goods.', basis: 'Barrels Turns'));
  }
  if (s.contains('gives_up_turn')) {
    insights.add(ReadInsight('Float the flop in position and take it away on the turn when they check — they\'re one-and-done.', basis: 'Gives Up Turn'));
  }
  if (s.contains('floats_wide')) {
    insights.add(ReadInsight('Barrel turn and river for value and as a bluff, and size up — make their wide floats pay.', basis: 'Floats Wide'));
  }
  if (s.contains('donk_leads')) {
    insights.add(ReadInsight('Their leads are usually a weak made hand or a draw — raise your value to deny equity; respect only a big lead into multiway.', basis: 'Donk-Leads'));
  }
  if (s.contains('over_bluffs')) {
    insights.add(ReadInsight('Call rivers lighter — they over-bluff missed draws.', basis: 'Over-Bluffs'));
  }
  if (s.contains('value_heavy')) {
    insights.add(ReadInsight('Fold to large bets unless you have the nuts or near-nuts.', basis: 'Value-Heavy'));
    insights.add(ReadInsight('Bluff them on boards where their value range is capped.'));
  }
  if (s.contains('overfolds_river')) {
    insights.add(ReadInsight('Triple-barrel bluff rivers more, especially on scare cards — they hero-fold too often.', basis: 'Overfolds River'));
  }
  if (s.contains('slow_plays')) {
    insights.add(ReadInsight('Be cautious when they check-call passively — they may be trapping.', basis: 'Slow-Plays'));
  }
  if (s.contains('check_raises')) {
    insights.add(ReadInsight('Bet smaller on boards where they check-raise — or check behind for pot control.', basis: 'Check-Raises'));
  }
  if (s.contains('readable_sizing')) {
    insights.add(ReadInsight('Use their bet sizing as a tell: fold marginal hands to the big bets, attack the small ones.', basis: 'Readable Sizing'));
  }

  // ── Tournament / ICM tendencies ─────────────────────────────────────────
  if (s.contains('tightens_bubble')) {
    insights.add(ReadInsight('Pile on the pressure near the bubble — open and re-shove on their stack; they fold to survive.', basis: 'Tightens at Bubble'));
  }
  if (s.contains('shoves_wide_short')) {
    insights.add(ReadInsight('Call their short-stack shoves wider — they jam far too light to fold equity.', basis: 'Shoves Wide (Short)'));
  }
  if (s.contains('calls_shoves_light')) {
    insights.add(ReadInsight('Shove tight for value and stop bluff-shoving — they call off too light.', basis: 'Calls Shoves Light'));
  }

  return insights;
}
