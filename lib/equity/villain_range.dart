// Range-aware villain modeling for the deterministic equity cross-check.
//
// For each opponent in a recorded hand we assign a preflop range from the GTO
// preset charts (keyed by their preflop line: open / call / 3-bet / limp,
// bucketed by the opener's position), adjust it for any reads tags on that
// player (LAG widens, Nit tightens, …), then narrow it street by street from
// their postflop actions (a bet keeps the top of the range, a raise keeps
// less, a check keeps everything). Hero's exact hole cards are then simulated
// against the modeled range(s) per street with the existing Monte Carlo
// engine — a number the AI coaching can be checked against.
//
// Everything here is deliberately deterministic and explainable: each villain
// carries a human-readable `rangeTrail` describing exactly which chart and
// which narrowing steps produced the number, because the feature exists to
// build trust ("here is the assumption — attack it if you disagree").

import 'dart:math';

import 'compute_compat.dart';

import '../models/hand_model.dart';
import '../models/player_read.dart';
import 'card.dart';
import 'chart_keys.dart';
import 'decision_context.dart';
import 'evaluator.dart';
import 'gto_frequency_library.dart';
import 'simulator.dart';

// ── Result types ──────────────────────────────────────────────────────────────

class StreetEquityCheck {
  final Street street;

  /// Hero's equity (0–1) entering this street, vs all modeled villains.
  final double heroEquity;
  final List<String> boardSoFar;
  final int villainCount;
  final int iterations;

  /// EQR (Decision-Context Engine, Tier A): hero's equity discounted for
  /// position + hand class — the figure the continue decision should weigh.
  /// All three are null pre-flop or when hero's position can't be determined.
  final double? realizedEquity;
  final HandClass? realizedHandClass;
  final bool? heroInPosition;

  /// SPR (DCE Tier A): effective stack ÷ pot at the START of this street, the
  /// heads-up required equity to stack off, and whether the pot was heads-up
  /// entering the street. All null pre-flop / when undeterminable (no pot, or
  /// hero/villains already all-in). [reqStackOffEquity] is null in a multiway
  /// pot — the all-in price there exceeds the heads-up figure, so the FACT
  /// reasons qualitatively from [spr] instead of asserting a precise %.
  final double? spr;
  final double? reqStackOffEquity;
  final bool? sprIsHeadsUp;

  /// GTO frequency library (DCE Q1): the decision-node type hero faced on this
  /// street — first_to_act / facing_check / facing_bet_small·mid·big /
  /// facing_raise — derived from the recorded action order. Null when hero took
  /// no action on the street (no decision to ground). The bet-size bucket is a
  /// soft approximation of the solver tree's sizes (live bets are arbitrary).
  final String? heroFacing;

  /// Multiway-tendency FACT inputs. [betHeroFaced] = the largest bet hero faced
  /// this street (null if none) — the gate for the line. [multiwayFieldMdf] = the
  /// FIELD's collective minimum-defense frequency pot/(pot+bet) for a CLEAN
  /// single-bet multiway spot, or null heads-up / when hero faced no bet / when
  /// hero faced a RAISE (the street-start pot would then mis-size it, so no %).
  final int? betHeroFaced;
  final double? multiwayFieldMdf;

  const StreetEquityCheck({
    required this.street,
    required this.heroEquity,
    required this.boardSoFar,
    required this.villainCount,
    required this.iterations,
    this.realizedEquity,
    this.realizedHandClass,
    this.heroInPosition,
    this.spr,
    this.reqStackOffEquity,
    this.sprIsHeadsUp,
    this.heroFacing,
    this.betHeroFaced,
    this.multiwayFieldMdf,
  });
}

class VillainModel {
  final String name;
  final String position;

  /// True when the villain's actual hole cards were recorded (showdown) —
  /// the equity is then exact, no range assumption needed.
  final bool usedExactCards;

  /// Reads tags that adjusted the modeled range (display names).
  final List<String> appliedTags;

  /// One line per modeling step, e.g.
  /// "Pre-flop: open-raised → BTN opening range (~46% of hands)".
  final List<String> rangeTrail;

  const VillainModel({
    required this.name,
    required this.position,
    required this.usedExactCards,
    required this.appliedTags,
    required this.rangeTrail,
  });
}

class HandEquityCheck {
  final List<StreetEquityCheck> streets;
  final List<VillainModel> villains;

  /// Quick Hand entries synthesize the action around the one recorded
  /// decision — the range model is built on that scaffolding, so the UI
  /// should say so.
  final bool basedOnSynthesizedAction;

  /// GTO frequency library (DCE Q1): which precomputed scenario this hand maps
  /// to ('srp_late_v_bb' = BTN open vs BB call; '3bp_bb_v_btn' = BTN open, BB
  /// 3-bet, BTN call), or null when it's outside the library's coverage (not
  /// heads-up, 4-bet+, seats/roles that don't match a solved pair, …).
  /// Gates the `[HEURISTIC — GTO frequency]` FACT to spots the library models.
  final String? scenarioKey;

  const HandEquityCheck({
    required this.streets,
    required this.villains,
    required this.basedOnSynthesizedAction,
    this.scenarioKey,
  });
}

/// Renders a [HandEquityCheck] into deterministic `[FACT —]` lines for the
/// `analyze-hand` prompt — the equity the model must not contradict, plus the
/// range assumption behind it. Returns an empty list when there is nothing to
/// assert. These are computed on-device, never by the model.
List<String> equityCheckFacts(HandEquityCheck check,
    {GtoFrequencyLibrary? library}) {
  if (check.streets.isEmpty) return const [];
  final perStreet = check.streets
      .map((s) => '${s.street.label.toLowerCase()} ~${(s.heroEquity * 100).round()}%')
      .join(', ');
  final caveat = check.basedOnSynthesizedAction
      ? ' The earlier action is synthesized (Quick Hand entry), so treat these '
          'as approximate, but the decision-street number is grounded in the '
          'recorded action and reads.'
      : '';
  final facts = <String>[
    '[FACT — Hero equity vs the modeled villain range(s), computed on-device '
        'by Monte Carlo (${check.streets.first.iterations} trials), NOT by you: '
        '$perStreet. These are deterministic ground truth — your assessment of '
        'each street MUST be consistent with them. The modeled villain ranges '
        'already include a GTO-balanced share of bluffs, so this is hero\'s true '
        'bluff-catch equity — compare it directly to any pot-odds price FACT '
        '(whether labelled "Price for hero to call" or "Price hero was getting '
        'when he folded") to decide call vs fold. A low number means hero '
        'loses to most of villain\'s range and is at best a weak bluff-catcher.'
        '$caveat]',
  ];
  for (final v in check.villains.where((v) => !v.usedExactCards)) {
    facts.add('[FACT — Villain ${v.name} (${v.position}) range behind the '
        'equity above: ${v.rangeTrail.join('; ')}.]');
  }
  // EQR (DCE Tier A): a single HEURISTIC line giving per-street realized equity.
  final realized = check.streets
      .where((s) =>
          s.realizedEquity != null &&
          s.realizedHandClass != null &&
          s.heroInPosition != null)
      .toList();
  if (realized.isNotEmpty) {
    final parts = realized
        .map((s) =>
            '${s.street.label.toLowerCase()} ~${(s.heroEquity * 100).round()}% → '
            'realized ~${(s.realizedEquity! * 100).round()}% '
            '(${s.heroInPosition! ? 'IP' : 'OOP'}, ${handClassLabel(s.realizedHandClass!)})')
        .join('; ');
    facts.add('[HEURISTIC — Equity REALIZATION (raw equity discounted for hero\'s '
        'position + hand class; ESTIMATED, not exact): $parts. A marginal hand out '
        'of position rarely realizes its raw equity; a strong made hand '
        'over-realizes. Weigh the continue / bluff-catch read against the REALIZED '
        'figure, not the raw one — but this is heuristic context: a decisive '
        'pot-odds price FACT and the hard equity FACT above still take precedence.]');
  }
  // SPR & COMMITMENT (DCE Tier A): one HEURISTIC line, per postflop street. The
  // stack-off % is heads-up-only; multiway emits SPR + a "beat the field" note.
  final sprStreets = check.streets.where((s) => s.spr != null).toList();
  if (sprStreets.isNotEmpty) {
    final parts = sprStreets.map((s) {
      final spr = s.spr!;
      final bucket = sprBucketLabel(sprBucket(spr));
      // Branch on the heads-up flag (reqStackOffEquity is non-null exactly when
      // heads-up); this is the field's one production consumer.
      final price = s.sprIsHeadsUp!
          ? 'to get all-in profitably needs ~${(s.reqStackOffEquity! * 100).round()}% equity'
          : 'multiway, so the stack-off price exceeds that heads-up figure (hero must beat the field)';
      return '${s.street.label.toLowerCase()} SPR ~${spr.toStringAsFixed(1)} — $price ($bucket)';
    }).join('; ');
    // Quick Hand entries synthesize stacks, so the SPR + stack-off % are only
    // as reliable as those — caveat them as the equity FACT already does.
    final synthCaveat = check.basedOnSynthesizedAction
        ? ' The stacks behind this come from a synthesized (Quick Hand) entry, '
            'so treat the SPR and stack-off % as rough.'
        : '';
    facts.add('[HEURISTIC — SPR & COMMITMENT (effective stack ÷ pot, hero-centric; '
        'ESTIMATED, not exact): $parts. Use this for the call-vs-raise / stack-off '
        'decision, NOT the bluff-catch call (pot odds govern that): at low SPR a '
        'strong-enough made hand should commit, at high SPR a one-pair hand favours '
        'pot control. With a marginal made hand villain\'s stack-off range skews to '
        'sets/two-pair, so require more than the raw %. The stack-off % is the equity '
        'to get all-in profitably versus a willing range, NOT hero\'s pot-odds price. '
        'This is heuristic context — a decisive pot-odds price FACT and the hard '
        'equity FACT still take precedence.$synthCaveat]');
  }
  // GTO FREQUENCY (DCE Q1): solver baseline for how often to take each action,
  // heads-up only, gated to the library's scenario. A soft prior — never a read.
  facts.addAll(_gtoFrequencyFacts(check, library));
  // MULTIWAY TENDENCY (DCE Q1): closed-form MDF + directional, NO % — for the
  // pots the solver can't model.
  facts.addAll(_multiwayTendencyFacts(check));
  return facts;
}

/// `[HEURISTIC — GTO frequency]` lines: per heads-up street, look up the offline
/// solver mix for hero's {texture, SPR, position, facing, hand class} and render
/// it. Empty unless the hand is in the library's scenario and a cell is found.
List<String> _gtoFrequencyFacts(
    HandEquityCheck check, GtoFrequencyLibrary? library) {
  if (library == null || library.isEmpty || check.scenarioKey == null) {
    return const [];
  }
  final parts = <String>[];
  var anyInterpolated = false;
  for (final s in check.streets) {
    if (s.villainCount != 1) continue; // heads-up only
    if (s.heroFacing == null ||
        s.heroInPosition == null ||
        s.realizedHandClass == null ||
        s.spr == null) {
      continue;
    }
    final res = library.lookup(
      scenario: check.scenarioKey!,
      board: boardInts(s.boardSoFar),
      sprBucket: sprBucket(s.spr!).name,
      street: s.street.label.toLowerCase(),
      position: s.heroInPosition! ? 'ip' : 'oop',
      facing: s.heroFacing!,
      handClass: s.realizedHandClass!,
    );
    if (res == null) continue;
    if (res.isInterpolated) anyInterpolated = true;
    final mix = (res.freqs.entries.where((e) => e.value >= 0.01).toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '${_freqActionLabel(e.key)} ~${(e.value * 100).round()}%')
        .join(', ');
    parts.add('${s.street.label.toLowerCase()} '
        '(${s.heroInPosition! ? 'IP' : 'OOP'}, '
        '${handClassLabel(s.realizedHandClass!)}, ${_facingLabel(s.heroFacing!)}): $mix');
  }
  if (parts.isEmpty) return const [];
  final softNote = anyInterpolated
      ? ' Some values are interpolated from a near texture/SPR — treat as looser.'
      : '';
  return [
    '[HEURISTIC — GTO frequency (a balanced solver baseline for how often to take '
        'each action with hero\'s hand class on this texture, from offline solves '
        'of this exact spot type — a soft PRIOR for frequency, NOT a read on this '
        'specific hand): ${parts.join('; ')}. Use it to sanity-check whether '
        'hero\'s line is a normal part of a balanced strategy; it is NEVER by '
        'itself a reason to mark a street wasGto:false or set leakDetected, and a '
        'hard [FACT —] or a decisive pot-odds price still decides the spot.$softNote]'
  ];
}

/// `[HEURISTIC — multiway tendency]` line: for multiway pots (no solver model),
/// the FIELD's collective MDF (a per-street COLLECTIVE ceiling, not a per-player
/// target) + directional guidance. The % is the field's, and only shown for a
/// clean single-bet spot where it is exactly derivable.
List<String> _multiwayTendencyFacts(HandEquityCheck check) {
  final parts = <String>[];
  for (final s in check.streets) {
    if (s.villainCount <= 1) continue; // multiway only
    if (s.betHeroFaced == null || s.betHeroFaced! <= 0) continue; // faced a bet
    final mdf = s.multiwayFieldMdf;
    final ceiling = mdf != null
        ? 'the FIELD must collectively defend ~${(mdf * 100).round()}% (MDF) — '
            'split across the ${s.villainCount + 1} players, so each defends a '
            'SMALLER share than a heads-up ceiling'
        : 'the FIELD\'s collective defense (MDF) is split across the '
            '${s.villainCount + 1} players, so each defends a SMALLER share than '
            'a heads-up ceiling';
    parts.add('${s.street.label.toLowerCase()} (${s.villainCount + 1}-way): $ceiling');
  }
  if (parts.isEmpty) return const [];
  return [
    '[HEURISTIC — multiway tendency (no solver model — solvers are heads-up only): '
        '${parts.join('; ')}. Multiway, a balanced strategy bluffs less and '
        'value-bets tighter than heads-up; this is directional context only — it '
        'is NEVER by itself a reason to mark a street wasGto:false or set '
        'leakDetected, and a hard [FACT —] or a decisive pot-odds price still '
        'decides hero\'s call (never an exact per-hand GTO frequency).]'
  ];
}

/// Human label for a library action key in the FACT prose.
String _freqActionLabel(String action) {
  switch (action) {
    case 'check':
      return 'check';
    case 'call':
      return 'call';
    case 'fold':
      return 'fold';
    case 'raise':
      return 'raise';
    case 'allin':
      return 'all-in';
    case 'bet':
      return 'bet';
    case 'bet_small':
      return 'small bet';
    case 'bet_mid':
      return 'medium bet';
    case 'bet_big':
      return 'big bet';
    default:
      return action;
  }
}

/// Human label for a facing-node key in the FACT prose.
String _facingLabel(String facing) {
  switch (facing) {
    case 'first_to_act':
      return 'first to act';
    case 'facing_check':
      return 'after a check to hero';
    case 'facing_bet_small':
      return 'facing a small bet';
    case 'facing_bet_mid':
      return 'facing a medium bet';
    case 'facing_bet_big':
      return 'facing a big bet';
    case 'facing_raise':
      return 'facing a raise';
    default:
      return facing.replaceAll('_', ' ');
  }
}

/// Hero's postflop position vs the contesting field: true = in position (acts
/// last). Read from the first-appearance order of seats on the FLOP (postflop
/// position is constant). Null when undeterminable (no flop, or hero/villains
/// absent from the flop action order) — callers then skip the EQR FACT rather
/// than guess a position.
bool? _heroInPosition(PokerHand hand, int heroSeat, Set<int> villainSeats) {
  for (final s in hand.streets) {
    if (s.street != Street.flop) continue;
    final order = <int>[];
    for (final a in s.actions) {
      if (!order.contains(a.seat)) order.add(a.seat);
    }
    final hi = order.indexOf(heroSeat);
    if (hi < 0) return null;
    var maxV = -1;
    for (final vs in villainSeats) {
      final i = order.indexOf(vs);
      if (i > maxV) maxV = i;
    }
    return maxV < 0 ? null : hi > maxV;
  }
  return null;
}

// ── Chen-formula hand ranking ─────────────────────────────────────────────────
// Used to widen/tighten a chart range for reads tags: widening adds the next
// strongest hands not already in the range; tightening keeps the top of it.

const String _rankOrder = 'AKQJT98765432';

double chenScore(String hand) {
  double pts(String r) {
    switch (r) {
      case 'A':
        return 10;
      case 'K':
        return 8;
      case 'Q':
        return 7;
      case 'J':
        return 6;
      case 'T':
        return 5;
      default:
        return (_rankOrder.length - _rankOrder.indexOf(r) + 1) / 2;
    }
  }

  final hi = pts(hand[0]);
  if (hand.length == 2) return max(5.0, hi * 2); // pair
  final suited = hand[2] == 's';
  final gap = _rankOrder.indexOf(hand[1]) - _rankOrder.indexOf(hand[0]) - 1;
  var score = hi;
  if (suited) score += 2;
  if (gap == 1) score -= 1;
  if (gap == 2) score -= 2;
  if (gap == 3) score -= 4;
  if (gap >= 4) score -= 5;
  // Connected or one-gap cards below queen can make hidden straights.
  if (gap <= 1 && _rankOrder.indexOf(hand[0]) >= 3) score += 1;
  return score;
}

int _combosOf(String hand) =>
    hand.length == 2 ? 6 : (hand[2] == 's' ? 4 : 12);

List<String> _buildRanking() {
  final hands = <String>[];
  for (var i = 0; i < 13; i++) {
    for (var j = i; j < 13; j++) {
      if (i == j) {
        hands.add('${kMatrixRanks[i]}${kMatrixRanks[j]}');
      } else {
        hands.add('${kMatrixRanks[i]}${kMatrixRanks[j]}s');
        hands.add('${kMatrixRanks[i]}${kMatrixRanks[j]}o');
      }
    }
  }
  hands.sort((a, b) {
    final c = chenScore(b).compareTo(chenScore(a));
    if (c != 0) return c;
    final hi = _rankOrder.indexOf(a[0]).compareTo(_rankOrder.indexOf(b[0]));
    if (hi != 0) return hi;
    final lo = _rankOrder.indexOf(a[1]).compareTo(_rankOrder.indexOf(b[1]));
    if (lo != 0) return lo;
    return a.length.compareTo(b.length) != 0
        ? a.length.compareTo(b.length)
        : a.compareTo(b); // pair < suited/offsuit; 'o' > 's'
  });
  return hands;
}

/// All 169 hand notations, strongest first (Chen formula).
final List<String> kRankedHands = _buildRanking();

final Map<String, int> _rankPos = {
  for (var i = 0; i < kRankedHands.length; i++) kRankedHands[i]: i,
};

/// Grow or shrink a notation range to roughly `factor` × its combo count.
/// Widening adds the strongest hands not in the range; tightening keeps the
/// strongest hands in it. factor 1.0 returns the range unchanged.
Set<String> adjustRangeSize(Set<String> base, double factor) {
  if (base.isEmpty || (factor - 1.0).abs() < 0.01) return base;
  final baseCombos = base.fold(0, (s, h) => s + _combosOf(h));
  final target = (baseCombos * factor).round();
  if (factor > 1) {
    final out = {...base};
    var total = baseCombos;
    for (final h in kRankedHands) {
      if (total >= target) break;
      if (out.add(h)) total += _combosOf(h);
    }
    return out;
  }
  final sorted = base.toList()
    ..sort((a, b) => (_rankPos[a] ?? 999).compareTo(_rankPos[b] ?? 999));
  final out = <String>{};
  var total = 0;
  for (final h in sorted) {
    out.add(h);
    total += _combosOf(h);
    if (total >= target) break;
  }
  return out;
}

// ── Preflop line classification ───────────────────────────────────────────────

enum _PreAct { none, checkedBb, limped, called, open, threeBet, fourBetPlus }

class _PreflopLine {
  _PreAct act = _PreAct.none;
  int calledAtLevel = 0; // raise count when the villain last called
  int? openerSeat; // seat of the first raiser in the hand
  bool folded = false;
}

_PreflopLine _classifyPreflop(StreetData preflop, int villainSeat) {
  final line = _PreflopLine();
  var level = 0;
  for (final a in preflop.actions) {
    switch (a.type) {
      case ActionType.post:
      case ActionType.postStraddle:
        break;
      case ActionType.raise:
      case ActionType.allIn:
        level++;
        line.openerSeat ??= a.seat;
        if (a.seat == villainSeat) {
          line.act = level <= 1
              ? _PreAct.open
              : (level == 2 ? _PreAct.threeBet : _PreAct.fourBetPlus);
        }
      case ActionType.call:
        if (a.seat == villainSeat) {
          line.act = level == 0 ? _PreAct.limped : _PreAct.called;
          line.calledAtLevel = level;
        }
      case ActionType.check:
        if (a.seat == villainSeat && level == 0 && line.act == _PreAct.none) {
          line.act = _PreAct.checkedBb;
        }
      case ActionType.fold:
        if (a.seat == villainSeat) line.folded = true;
    }
  }
  return line;
}

// ── Chart selection ───────────────────────────────────────────────────────────
// Position→chart-key mapping lives in chart_keys.dart (shared with quick-hand
// synthesis). Here we only resolve a key to its hand set, falling back to
// any-two when a key is missing.

Set<String> get _anyTwo => kRankedHands.toSet();

Set<String> _chart(String key) => presetByKey[key] ?? _anyTwo;

// ── Tag adjustments ───────────────────────────────────────────────────────────

double _preflopTagFactor(Set<String> tags, _PreAct act) {
  final aggressive = act == _PreAct.open ||
      act == _PreAct.threeBet ||
      act == _PreAct.fourBetPlus;
  var f = 1.0;
  if (tags.contains('maniac')) f *= 2.0;
  if (tags.contains('lag_player')) f *= 1.5;
  if (tags.contains('fish')) f *= aggressive ? 1.2 : 1.6;
  if (tags.contains('calling_station') && !aggressive) f *= 1.8;
  if (tags.contains('nit')) f *= 0.6;
  if (tags.contains('opens_wide') && act == _PreAct.open) f *= 1.5;
  if (tags.contains('opens_tight') && act == _PreAct.open) f *= 0.65;
  if (tags.contains('three_bets_light') && act == _PreAct.threeBet) f *= 1.8;
  if (tags.contains('four_bets_light') && act == _PreAct.fourBetPlus) {
    f *= 1.6;
  }
  return f.clamp(0.35, 3.0);
}

double _preflopCallTagFactor(Set<String> tags, int calledAtLevel) {
  var f = 1.0;
  if (calledAtLevel >= 2) {
    if (tags.contains('calls_3bet_wide')) f *= 1.5;
    if (tags.contains('folds_3bet')) f *= 0.7;
  }
  return f;
}

double _postflopTagFactor(
    Set<String> tags, _StreetAct act, Street street) {
  var f = 1.0;
  final aggressive = act == _StreetAct.bet ||
      act == _StreetAct.raise ||
      act == _StreetAct.allIn;
  if (aggressive) {
    if (tags.contains('maniac')) f *= 1.6;
    if (tags.contains('lag_player')) f *= 1.3;
    if (tags.contains('over_bluffs')) f *= 1.5;
    if (tags.contains('c_bets_always') &&
        street == Street.flop &&
        act == _StreetAct.bet) {
      f *= 1.5;
    }
    if (tags.contains('nit')) f *= 0.7;
    if (tags.contains('value_heavy')) f *= 0.6;
  } else if (act == _StreetAct.call) {
    if (tags.contains('calling_station')) f *= 1.45;
    if (tags.contains('fish')) f *= 1.3;
    if (tags.contains('floats_wide') && street == Street.flop) f *= 1.35;
    if (tags.contains('folds_to_cbet')) f *= 0.7;
    if (tags.contains('nit')) f *= 0.75;
    if (tags.contains('overfolds_river') && street == Street.river) f *= 0.7;
  }
  return f;
}

// ── Postflop combo scoring ────────────────────────────────────────────────────
// Deterministic strength score on the current board: the 5-card evaluator
// value plus a draw bonus on flop/turn, so semi-bluff hands (flush draws,
// OESDs) survive a bet filter the way real betting ranges keep them.

const int _kFlushDrawBonus = 0x0F0000; // just below one pair (0x100000)
const int _kOesdBonus = 0x0D0000;
const int _kGutshotBonus = 0x050000;

int _drawBonus(List<int> cards) {
  // Flush draw: exactly 4 of one suit.
  var bonus = 0;
  final suitCount = List.filled(4, 0);
  for (final c in cards) {
    suitCount[cardSuit(c)]++;
  }
  if (suitCount.any((n) => n == 4)) bonus += _kFlushDrawBonus;

  // Straight draws: rank windows with exactly 4 of 5 ranks present.
  final vals = <int>{};
  for (final c in cards) {
    final v = cardRank(c) + 2;
    vals.add(v);
    if (v == 14) vals.add(1); // wheel ace
  }
  var made = false;
  final completing = <int>{};
  for (var low = 1; low <= 10; low++) {
    var present = 0;
    var missing = 0;
    for (var v = low; v < low + 5; v++) {
      if (vals.contains(v)) {
        present++;
      } else {
        missing = v;
      }
    }
    if (present == 5) {
      made = true;
      break;
    }
    if (present == 4) completing.add(missing);
  }
  if (!made) {
    if (completing.length >= 2) {
      bonus += _kOesdBonus;
    } else if (completing.length == 1) {
      bonus += _kGutshotBonus;
    }
  }
  return bonus;
}

int _comboScore(List<int> combo, List<int> board, {required bool isRiver}) {
  final cards = [...combo, ...board];
  var score = evaluateBest(cards);
  if (!isRiver) score += _drawBonus(cards);
  return score;
}

// ── Street action classification ──────────────────────────────────────────────

enum _StreetAct { none, check, call, bet, raise, allIn, fold }

/// Classifies one action. Any all-in counts as [_StreetAct.allIn] regardless
/// of base type — the full Hand wizard records all-ins as a raise/call with
/// `isAllIn: true` (only Quick Hand synthesis emits [ActionType.allIn]), so
/// keying off `type` alone would narrow an all-in range far too wide.
_StreetAct _actOf(HandAction a) {
  if (a.isAllIn) return _StreetAct.allIn;
  return switch (a.type) {
    ActionType.check => _StreetAct.check,
    ActionType.call => _StreetAct.call,
    ActionType.raise => a.isOpeningBet ? _StreetAct.bet : _StreetAct.raise,
    ActionType.allIn => _StreetAct.allIn,
    ActionType.fold => _StreetAct.fold,
    ActionType.post || ActionType.postStraddle => _StreetAct.none,
  };
}

_StreetAct _strongestAction(StreetData street, int seat) {
  var strongest = _StreetAct.none;
  for (final a in street.actions) {
    if (a.seat != seat) continue;
    final act = _actOf(a);
    if (act.index > strongest.index) strongest = act;
  }
  // A fold defines the range only when it's the villain's sole action; if they
  // acted before folding (bet, then folded to a raise), that prior action is
  // what defines the range entering the street. Fold has the highest index, so
  // unwind it.
  if (strongest == _StreetAct.fold) return _strongestNonFold(street, seat);
  return strongest;
}

_StreetAct _strongestNonFold(StreetData street, int seat) {
  var strongest = _StreetAct.none;
  for (final a in street.actions) {
    if (a.seat != seat || a.type == ActionType.fold) continue;
    final act = _actOf(a);
    if (act.index > strongest.index) strongest = act;
  }
  return strongest;
}

/// Per-action narrowing parameters. `value` = fraction of the (board-filtered)
/// range kept from the strong top; `bluff` = fraction kept from the weak bottom
/// as bluffs (0 for passive actions). A non-zero `bluff` makes the kept range
/// POLARIZED (top value + busted-draw/air tail, the medium middle dropped) —
/// the shape of a real betting/raising range, and what lets a bluff-catcher
/// keep realistic equity instead of collapsing to ~0 against a value-only
/// slice. Calls keep the contiguous, capped top (a merged/condensed range).
/// Default bluff sizing is GTO-balanced (~2:1 value:bluff); reads move it via
/// [_bluffTagFactor].
// A small/blocker sizing (as a fraction of the pot before the action) is MERGED,
// not polarized — a WIDE value-leaning range that still retains some bluffs, not
// a tight nuts-or-air barbell. Bigger sizings keep the tighter, more polar base
// split. Without this, a min/blocker bet was modeled (and labeled) identically
// to a pot bet — the bug: a tiny ~11%-pot river bet read as "polarized".
const double _kSmallBetFrac = 0.4; // ≤ ~⅓-pot → merged

({double value, double bluff}) _keepFractions(_StreetAct act,
        [double? sizeFrac]) =>
    switch (act) {
      _StreetAct.allIn ||
      _StreetAct.raise ||
      _StreetAct.bet =>
        _aggressiveFractions(act, sizeFrac),
      _StreetAct.call => (value: 0.65, bluff: 0.0),
      _ => (value: 1.0, bluff: 0.0),
    };

/// Value/bluff split for a bet/raise/all-in, modulated by bet size. [sizeFrac]
/// is the wager as a fraction of the pot before it (null = unknown → base).
({double value, double bluff}) _aggressiveFractions(
    _StreetAct act, double? sizeFrac) {
  final base = switch (act) {
    _StreetAct.allIn => (value: 0.18, bluff: 0.07),
    _StreetAct.raise => (value: 0.22, bluff: 0.09),
    _ => (value: 0.30, bluff: 0.15), // bet
  };
  // Small/blocker sizing → merged: WIDEN the value top (less polar) while
  // RETAINING a bluff tail. The wider top must still drop SOME of the range or
  // the action is a no-op, and the kept bluffs keep a bluff-catcher's equity
  // realistic (dropping them re-creates the value-only-slice collapse).
  if (sizeFrac != null && sizeFrac < _kSmallBetFrac) {
    return (value: max(base.value, 0.55), bluff: max(base.bluff, 0.12));
  }
  return base;
}

// ── GTO frequency library (DCE Q1) key derivation ───────────────────────────

/// The decision-node type hero faced on [street] (the library's "facing" key),
/// or null when hero took no action there. Derived from the recorded order: the
/// opponent action immediately before hero's LAST action this street — so a
/// check-then-call line reads as facing_bet (the call), a lead reads as
/// first_to_act, and a check-to-hero reads as facing_check.
String? _heroFacing(StreetData street, int heroSeat, int potBeforeStreet) {
  final acts = street.actions;
  var heroLast = -1;
  for (var i = 0; i < acts.length; i++) {
    if (acts[i].seat == heroSeat) heroLast = i;
  }
  if (heroLast < 0) return null; // hero didn't act → no decision to ground
  var prevIdx = -1;
  for (var i = heroLast - 1; i >= 0; i--) {
    if (acts[i].seat != heroSeat) {
      prevIdx = i;
      break;
    }
  }
  if (prevIdx < 0) return 'first_to_act'; // hero opened the street
  final prev = acts[prevIdx];
  switch (prev.type) {
    case ActionType.check:
      return 'facing_check';
    case ActionType.raise:
    case ActionType.allIn:
      // A bet is the first aggression this street; aggression after a prior
      // bet/raise is a raise.
      final priorAggression = acts.take(prevIdx).any(
          (a) => a.type == ActionType.raise || a.type == ActionType.allIn);
      if (priorAggression) return 'facing_raise';
      return 'facing_bet_'
          '${_facingBetBucket(_betSizeFrac(street, prev.seat, potBeforeStreet))}';
    default:
      return 'first_to_act'; // post/call/fold before hero → hero effectively leads
  }
}

/// Bucket a faced bet's pot-fraction into the library's size labels. Delegates
/// to the shared [betSizeBucket] (decision_context.dart) so the live lookup and
/// the offline tabulator bucket bets IDENTICALLY — see that function's note.
String _facingBetBucket(double? frac) => betSizeBucket(frac);

/// The largest outstanding bet/raise hero faced on [street] before his decision
/// (the MDF FACT's bet input), or null when hero faced no aggression. The MAX
/// (not just the immediately-preceding action) so a multiway pot where a caller
/// sits between the bettor and hero still sees the bet hero must call.
int? _betHeroFaced(StreetData street, int heroSeat) {
  final acts = street.actions;
  var heroLast = -1;
  for (var i = 0; i < acts.length; i++) {
    if (acts[i].seat == heroSeat) heroLast = i;
  }
  if (heroLast < 0) return null;
  int? maxBet;
  for (var i = 0; i < heroLast; i++) {
    final a = acts[i];
    if (a.seat == heroSeat) continue;
    if ((a.type == ActionType.raise || a.type == ActionType.allIn) &&
        a.amount != null &&
        (maxBet == null || a.amount! > maxBet)) {
      maxBet = a.amount;
    }
  }
  return maxBet;
}

/// The FIELD's collective minimum-defense frequency on [street] = pot/(pot+bet),
/// valid only when hero faces a CLEAN single bet (exactly one aggressive action
/// before hero's decision): only then is [potBeforeStreet] the true pre-bet pot.
/// Returns null on a bet-then-raise line (where the street-start pot mis-sizes
/// the MDF) or when hero faced no bet. The per-player share is below this — the
/// field splits the defense — so the FACT frames it as a collective ceiling.
double? _multiwayFieldMdf(
    StreetData street, int heroSeat, int potBeforeStreet) {
  if (potBeforeStreet <= 0) return null;
  final acts = street.actions;
  var heroLast = -1;
  for (var i = 0; i < acts.length; i++) {
    if (acts[i].seat == heroSeat) heroLast = i;
  }
  if (heroLast < 0) return null;
  HandAction? bet;
  for (var i = 0; i < heroLast; i++) {
    final a = acts[i];
    if (a.seat == heroSeat) continue;
    if (a.type == ActionType.raise || a.type == ActionType.allIn) {
      if (bet != null) return null; // a second aggression (raise) → pot is stale
      bet = a;
    }
  }
  if (bet?.amount == null || bet!.amount! <= 0) return null;
  return minDefenseFrequency(potBeforeStreet.toDouble(), bet.amount!.toDouble());
}

/// The GTO-library scenario this hand maps to, or null when outside coverage.
/// Keys must match the solve grid's kScenarios (tool/solver/freq_grid.dart):
///  - srp_late_v_bb — heads-up single-raised, BTN opener vs BB caller.
///  - 3bp_bb_v_btn — heads-up 3-bet pot: BTN open → BB 3-bet → BTN call
///    (the 3-bettor OOP). The BTN must be the ORIGINAL opener — a cold-called
///    3-bet or squeeze reaches the flop with different ranges than the solve.
/// Gates the GTO-frequency FACT.
String? _deriveScenarioKey(PokerHand hand, StreetData preflop, int heroSeat,
    List<_VillainState> modeled) {
  final contesting = modeled.where((v) => v.combos.isNotEmpty).toList();
  if (contesting.length != 1) return null; // not heads-up to the flop
  final villainSeat = contesting.single.player.seatIndex;
  final hl = _classifyPreflop(preflop, heroSeat);
  final vl = _classifyPreflop(preflop, villainSeat);
  bool tooDeep(_PreflopLine l) =>
      l.act == _PreAct.fourBetPlus || l.calledAtLevel >= 3;
  if (tooDeep(hl) || tooDeep(vl)) return null; // 4-bet+ pot
  String posOf(int seat) => hand.tableSetup.positionName(seat);

  // Single-raised: opener vs a caller of the open.
  int openerSeat, callerSeat;
  if (hl.act == _PreAct.open &&
      vl.act == _PreAct.called &&
      vl.calledAtLevel <= 1) {
    openerSeat = heroSeat;
    callerSeat = villainSeat;
  } else if (vl.act == _PreAct.open &&
      hl.act == _PreAct.called &&
      hl.calledAtLevel <= 1) {
    openerSeat = villainSeat;
    callerSeat = heroSeat;
  } else {
    // 3-bet pot: one player 3-bet, the other called AT level 2, and the caller
    // is the original opener (openerSeat = first raiser in the hand).
    int threeBetterSeat;
    if (hl.act == _PreAct.threeBet &&
        vl.act == _PreAct.called &&
        vl.calledAtLevel == 2) {
      threeBetterSeat = heroSeat;
      callerSeat = villainSeat;
    } else if (vl.act == _PreAct.threeBet &&
        hl.act == _PreAct.called &&
        hl.calledAtLevel == 2) {
      threeBetterSeat = villainSeat;
      callerSeat = heroSeat;
    } else {
      return null;
    }
    if (hl.openerSeat != callerSeat) return null; // caller must be the opener
    // Solved BB(OOP) 3-bettor vs BTN(IP) open-caller only — other seat pairs
    // have different ranges AND can invert IP/OOP (the lookup keys on physical
    // position).
    if (posOf(threeBetterSeat) != 'BB' || posOf(callerSeat) != 'BTN') {
      return null;
    }
    return '3bp_bb_v_btn';
  }
  // The SRP library was solved BTN(IP)-opener vs BB(OOP)-caller. The SB also
  // buckets as 'late' but opens OUT of position, so its IP/OOP cells would be
  // inverted (the lookup keys on physical position) — restrict to a BTN opener.
  if (posOf(openerSeat) != 'BTN') return null;
  if (posOf(callerSeat) != 'BB') return null;
  return 'srp_late_v_bb';
}

/// [seat]'s bet/raise on [street] sized as a fraction of the pot AT THE MOMENT
/// it was made — the chips that action committed over the pot it faced. Replays
/// the street from [potAtStreetStart] so a raise is measured against the pot
/// that already includes the bet it raises (not the street-start pot, which
/// would overstate every raise). For a first-in bet this is just bet ÷ pot.
/// Returns the strongest (last) aggressive action by [seat]; null if none.
double? _betSizeFrac(StreetData street, int seat, int potAtStreetStart) {
  if (potAtStreetStart <= 0) return null;
  var pot = potAtStreetStart.toDouble();
  final contrib = <int, int>{};
  double? sizeFrac;
  for (final a in street.actions) {
    final amt = a.amount;
    if (amt == null) continue; // check/fold commit no chips
    final inc = amt - (contrib[a.seat] ?? 0);
    if (inc <= 0) continue;
    final potFaced = pot;
    pot += inc;
    contrib[a.seat] = amt;
    final act = _actOf(a);
    final aggressive = act == _StreetAct.bet ||
        act == _StreetAct.raise ||
        act == _StreetAct.allIn;
    if (a.seat == seat && aggressive && potFaced > 0) {
      sizeFrac = inc / potFaced; // last aggressive action wins (the strongest)
    }
  }
  return sizeFrac;
}

/// How far a villain's bluff frequency deviates from the GTO-balanced default.
/// Value-heavy players and nits barely bluff; maniacs/over-bluffers fire air far
/// more often. Independent of the value-width factor (a nit value-bets a normal
/// width but almost never bluffs), so a tagged opponent's bluff-catch equity
/// moves the way the read implies.
double _bluffTagFactor(Set<String> tags) {
  var f = 1.0;
  if (tags.contains('over_bluffs')) f *= 1.6;
  if (tags.contains('maniac')) f *= 1.5;
  if (tags.contains('lag_player')) f *= 1.3;
  if (tags.contains('nit')) f *= 0.4;
  if (tags.contains('value_heavy')) f *= 0.3;
  return f.clamp(0.0, 2.5);
}

String _actLabel(_StreetAct act) => switch (act) {
      _StreetAct.allIn => 'all-in',
      _StreetAct.raise => 'raise',
      _StreetAct.bet => 'bet',
      _StreetAct.call => 'call',
      _StreetAct.check => 'check',
      _StreetAct.fold => 'fold',
      _StreetAct.none => 'no action',
    };

// ── Villain state through the hand ────────────────────────────────────────────

class _VillainState {
  final HandPlayer player;
  final String position;
  final Set<String> tags;
  final List<String> exactCards; // empty unless hole cards recorded
  List<List<int>> combos = [];
  final List<String> trail = [];
  bool excludedFromAllStreets = false;

  _VillainState(this.player, this.position, this.tags, this.exactCards);
}

String _pct(int combos) => '${(combos / 1326 * 100).round()}%';

// ── Entry point ───────────────────────────────────────────────────────────────

/// Computes hero's per-street equity against chart-derived, reads-adjusted,
/// action-narrowed villain ranges. Returns null when the hand can't be
/// modeled (no hero cards, no opponents, unparseable cards).
///
/// The whole computation — range building, per-street combo scoring/narrowing,
/// and the Monte Carlo sims — runs in ONE background isolate, so the heavy
/// brute-force scoring never blocks the UI thread and there is a single isolate
/// spawn per analysis rather than one per street.
Future<HandEquityCheck?> computeHandEquityCheck(
  PokerHand hand, {
  List<PlayerRead> reads = const [],
  int iterations = 10000,
  // null = nondeterministic (the app). Pass a fixed seed for reproducible
  // output — used by the eval-harness baker so checked-in fixtures don't churn.
  int? seed,
}) =>
    compute(
        _computeEquityCheckSync, _EquityArgs(hand, reads, iterations, seed));

class _EquityArgs {
  final PokerHand hand;
  final List<PlayerRead> reads;
  final int iterations;
  final int? seed;
  const _EquityArgs(this.hand, this.reads, this.iterations, this.seed);
}

HandEquityCheck? _computeEquityCheckSync(_EquityArgs args) {
  final hand = args.hand;
  final reads = args.reads;
  final iterations = args.iterations;
  final seed = args.seed;

  final hero = hand.hero;
  final heroCards = hero?.holeCards;
  if (hero == null || heroCards == null || heroCards.length != 2) return null;
  final h1 = parseCard(heroCards[0]);
  final h2 = parseCard(heroCards[1]);
  if (h1 < 0 || h2 < 0) return null;

  final opponents = hand.players.where((p) => !p.isHero).toList();
  if (opponents.isEmpty) return null;

  // Hero's postflop position vs the field (IP = acts last), from the flop action
  // order. Constant across postflop streets; feeds the EQR realized-equity FACT.
  final heroIp =
      _heroInPosition(hand, hero.seatIndex, opponents.map((o) => o.seatIndex).toSet());

  final preflop = hand.streets
      .where((s) => s.street == Street.preflop)
      .firstOrNull;
  if (preflop == null) return null;

  final readMap = {
    for (final r in reads) r.playerLabel.toLowerCase(): r.tags.toSet(),
  };

  // Dead cards for every villain range: hero's cards only. Recorded villain
  // hole cards (showdown) are deliberately NOT treated as known — using them
  // would make the equity result-dependent ("hero vs the one hand villain
  // turned over"), which craters to 0% exactly when the runout completes that
  // hand. Coaching must judge the decision under the uncertainty hero faced, so
  // every villain is modeled by RANGE regardless of what they later showed.
  final knownCards = <int>{h1, h2};

  final trn = hand.isTournament;
  final villains = <_VillainState>[];

  for (final p in opponents) {
    final pos = hand.tableSetup.positionName(p.seatIndex);
    final tags = readMap[p.name.toLowerCase()] ?? const <String>{};
    // Recorded showdown cards are intentionally ignored (see knownCards above)
    // so the cross-check stays result-independent: every villain is modeled by
    // range, never collapsed to the exact hand they later turned over.
    final v = _VillainState(p, pos, tags, const <String>[]);

    final line = _classifyPreflop(preflop, p.seatIndex);
    // A villain whose only preflop involvement was folding never contests the
    // pot — including them would just dilute hero's number with dead money.
    if (line.folded && line.act == _PreAct.none) {
      v.excludedFromAllStreets = true;
      villains.add(v);
      continue;
    }

    final pc = posClass(pos);
    final openerLabel = line.openerSeat != null
        ? hand.tableSetup.positionName(line.openerSeat!)
        : 'BTN';
    final bucket = openerBucketForLabel(openerLabel);

    Set<String> range;
    String desc;
    switch (line.act) {
      case _PreAct.open:
        final key = rfiKey(pos, trn) ?? '${trn ? 'trn' : 'cash'}_rfi_co';
        range = _chart(key);
        desc = 'open-raised → $pos opening range';
      case _PreAct.threeBet:
        range = _chart(threeBetKey(pc, bucket, trn));
        desc = '3-bet vs a $bucket-position open → 3-bet range';
      case _PreAct.fourBetPlus:
        range = _chart(fourBetKey(trn));
        desc = '4-bet+ → premium value range';
      case _PreAct.limped:
        range = _chart(trn ? 'trn_call_bb_vs_late' : 'cash_call_bb_vs_btn');
        desc = 'limped → wide passive range';
      case _PreAct.called:
        if (line.calledAtLevel >= 3) {
          range = _chart(fourBetKey(trn));
          desc = 'called a 4-bet → premium continue range';
        } else if (line.calledAtLevel == 2) {
          range = _chart(call3BetKey(pc, trn));
          desc = 'called a 3-bet → 3-bet-defense range';
        } else {
          range = _chart(callKey(pc, bucket, openerLabel, trn));
          desc = 'called a $bucket-position open → '
              '$pos defending range';
        }
      case _PreAct.checkedBb:
        range = _anyTwo;
        desc = pos == 'STR'
            ? 'checked the straddle option — any two cards'
            : 'checked the big blind — any two cards';
      case _PreAct.none:
        range = _anyTwo;
        desc = 'no preflop action recorded — any two cards';
    }

    final tagFactor = _preflopTagFactor(v.tags, line.act) *
        _preflopCallTagFactor(v.tags, line.calledAtLevel);
    var factor = tagFactor;
    // A straddler defending their straddle gets a price discount and closes
    // the action — wider than the BB chart baseline they're mapped onto.
    final straddleDefend = pos == 'STR' &&
        (line.act == _PreAct.called || line.act == _PreAct.limped);
    if (straddleDefend) {
      factor = (factor * 1.25).clamp(0.35, 3.0);
    }
    if (line.act == _PreAct.checkedBb || line.act == _PreAct.none) {
      factor = min(factor, 1.0); // can't widen any-two
    }
    final adjusted = adjustRangeSize(range, factor);

    final combos = <List<int>>[];
    for (final notation in adjusted) {
      final cell = handToCell(notation);
      for (final pair
          in expandCell(cell.$1, cell.$2, exclude: knownCards)) {
        combos.add([pair.$1, pair.$2]);
      }
    }
    v.combos = combos;

    var note = 'Pre-flop: $desc (~${_pct(combos.length)} of hands)';
    if (straddleDefend) {
      note += ' · straddle treated as a blind (BB defend charts, widened)';
    }
    if ((tagFactor - 1.0).abs() >= 0.01) {
      note += tagFactor > 1
          ? ' · widened ×${tagFactor.toStringAsFixed(1)} for reads'
          : ' · tightened ×${tagFactor.toStringAsFixed(1)} for reads';
    }
    v.trail.add(note);
    villains.add(v);
  }

  final modeled =
      villains.where((v) => !v.excludedFromAllStreets).toList();
  if (modeled.isEmpty || modeled.every((v) => v.combos.isEmpty)) return null;

  // GTO frequency library scenario (DCE Q1): hand-level, computed before the
  // streets narrow ranges (uses the preflop ranges).
  final scenarioKey = _deriveScenarioKey(hand, preflop, hero.seatIndex, modeled);

  // ── Walk the streets, narrowing and simulating ──────────────────────────
  final streetResults = <StreetEquityCheck>[];
  final boardSoFar = <int>[];
  final boardNames = <String>[];
  final foldedSeats = <int>{};
  // Pot at the start of the current street, so a villain's bet/raise can be
  // sized as a fraction of it (small → merged, big → polarized).
  var potBefore = 0;
  // Chips each seat has committed BEFORE the current street, so the per-street
  // effective stack (starting stack − committed) feeds the SPR computation.
  final committed = <int, int>{};

  for (final street in hand.streets) {
    for (final c in street.communityCards) {
      final idx = parseCard(c);
      if (idx >= 0) {
        boardSoFar.add(idx);
        boardNames.add(c);
      }
    }

    final active = modeled
        .where((v) =>
            !foldedSeats.contains(v.player.seatIndex) && v.combos.isNotEmpty)
        .toList();

    if (active.isNotEmpty) {
      // Narrow each active villain's range from their action on this street
      // (board-collision combos drop out first), then simulate.
      for (final v in active) {
        v.combos = v.combos
            .where((c) =>
                !boardSoFar.contains(c[0]) && !boardSoFar.contains(c[1]))
            .toList();
        if (street.street == Street.preflop) continue; // preflop range is set

        final act = _strongestAction(street, v.player.seatIndex);
        final aggressive = act == _StreetAct.bet ||
            act == _StreetAct.raise ||
            act == _StreetAct.allIn;
        // Bet size relative to the pot drives polar-vs-merged (small → merged).
        final sizeFrac = aggressive
            ? _betSizeFrac(street, v.player.seatIndex, potBefore)
            : null;
        final isSmallBet =
            sizeFrac != null && sizeFrac < _kSmallBetFrac;
        final sizeNote =
            sizeFrac != null ? ' (~${(sizeFrac * 100).round()}% pot)' : '';
        final fr = _keepFractions(act, sizeFrac);
        // Value width scales with the aggressive/passive tag factor (a maniac
        // value-bets wider, a nit tighter). Bluff width scales independently —
        // nits/value-heavy players almost never bluff, maniacs over-bluff.
        final valueFrac =
            (fr.value * _postflopTagFactor(v.tags, act, street.street))
                .clamp(0.06, 1.0);
        final bluffFrac = aggressive
            ? (fr.bluff * _bluffTagFactor(v.tags)).clamp(0.0, 0.6)
            : 0.0;

        if ((valueFrac >= 1.0 && bluffFrac <= 0.0) || v.combos.length <= 6) {
          if (act != _StreetAct.none) {
            v.trail.add('${street.street.label}: ${_actLabel(act)} → '
                'range unchanged');
          }
          continue;
        }

        final isRiver = street.street == Street.river;
        final scored = v.combos
            .map((c) => (c, _comboScore(c, boardSoFar, isRiver: isRiver)))
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
        final n = scored.length;
        final floor = max(6, (n * 0.04).round());
        final valueCount = max(floor, (n * valueFrac).round());

        if (bluffFrac <= 0.0) {
          // Merged / capped range (a call, or a tag-suppressed bluff-free
          // aggressor): keep the contiguous top by strength.
          v.combos = scored.take(valueCount).map((e) => e.$1).toList();
          v.trail.add('${street.street.label}: ${_actLabel(act)}$sizeNote → '
              'kept top ${(valueFrac * 100).round()}% of range');
        } else {
          // Polarized range: top value combos PLUS a tail of the weakest combos
          // (busted draws / air) as bluffs. The medium middle — hands that would
          // check rather than bet — is dropped. This is what keeps a
          // bluff-catcher's equity realistic against a bet/raise instead of
          // collapsing it to ~0 (the value-only-slice bug).
          // Floor of 1 combo whenever there is room: a villain who fires a bet
          // (let alone a triple-barrel) is never literally bluff-free, so a
          // bluff-catcher must never read a hard 0%. Reads still drive the
          // number low — they just can't zero it by rounding.
          final bluffCount = max(1, (n * bluffFrac).round())
              .clamp(0, max(0, n - valueCount))
              .toInt();
          v.combos = [
            ...scored.take(valueCount).map((e) => e.$1),
            if (bluffCount > 0)
              ...scored.sublist(n - bluffCount).map((e) => e.$1),
          ];
          // Report the bluffs actually kept, not the requested fraction — when
          // value already takes the whole range (valueFrac clamped to 1.0) or
          // the range is tiny, bluffCount can clamp to 0 or below the requested
          // %, and the trail must not claim a bluff tail that isn't there.
          final valPct = (valueFrac * 100).round();
          final blPct = (bluffCount / n * 100).round();
          v.trail.add(bluffCount > 0
              ? (isSmallBet
                  // A small/blocker bet is MERGED, not polarized: a wide
                  // value-leaning range that still carries some bluffs.
                  ? '${street.street.label}: small ${_actLabel(act)}$sizeNote → '
                      'merged, NOT polarized (wide value-leaning range with some '
                      'bluffs): top $valPct% strong + bottom $blPct% weak/bluffs'
                  : '${street.street.label}: ${_actLabel(act)}$sizeNote → '
                      'polarized: top $valPct% value + bottom $blPct% bluffs')
              : '${street.street.label}: ${_actLabel(act)}$sizeNote → kept top '
                  '$valPct% value (no bluffs added)');
        }
      }

      final simVillains =
          active.where((v) => v.combos.isNotEmpty).toList();
      if (simVillains.isNotEmpty) {
        // Synchronous: we are already inside the compute() isolate.
        final result = runSimulationSync(
          ranges: [
            [
              [h1, h2]
            ],
            ...simVillains.map((v) => v.combos),
          ],
          boardCards: [...boardSoFar],
          iterations: iterations,
          // Offset per street so each gets a distinct but reproducible stream.
          seed: seed != null ? seed + streetResults.length : null,
        );
        // EQR: discount raw equity for hero's hand class + position. Null (→ no
        // realized FACT) when pre-flop / unclassifiable / position unknown, OR
        // when the pot is MULTIWAY — IP/OOP is ill-defined when hero is in
        // position on one villain and out of position on another, so we only
        // assert realized equity in a heads-up pot.
        final hc = classifyHandClass([h1, h2], boardSoFar);
        final realizedEq =
            (hc != null && heroIp != null && simVillains.length == 1)
                ? realizedEquity(result.equity[0],
                    handClass: hc,
                    position: heroIp ? HeroPosition.ip : HeroPosition.oop)
                : null;
        // SPR (DCE Tier A): effective stack ÷ pot at street start. Effective
        // stack = min(hero remaining, the SHORTEST simulated villain remaining)
        // — the standard effective-stack convention (the shortest stack caps the
        // all-in everyone can match). Using the DEEPEST villain would overstate
        // SPR when the deepest opponent isn't the one driving the action (e.g. a
        // short aggressor beside a deep passive player). Scope to simVillains
        // (the opponents actually simulated this street), NOT `active`: a villain
        // whose range fully collides with the board narrows to zero combos and
        // drops from simVillains but stays in `active`, so keying off `active`
        // would read "multiway" while EQR (simVillains.length) reads heads-up on
        // the SAME street — contradicting FACTs. (A villain who folds ON this
        // street still counts here, mirroring the equity sim + EQR, which also
        // include the flop-folder in the flop number — a shared, pre-existing
        // convention, not specific to SPR.) Skipped pre-flop, with no pot, or
        // when the field is already all-in from a PRIOR street (committed then
        // covers the stack → effStack 0). The required-equity % is heads-up-only;
        // multiway it is null and the pot is flagged as such in the FACT.
        double? spr;
        double? reqStackOff;
        bool? sprHeadsUp;
        if (street.street != Street.preflop && potBefore > 0) {
          final heroRem = hero.startingStack - (committed[hero.seatIndex] ?? 0);
          int? shortestVillainRem;
          for (final v in simVillains) {
            final rem =
                v.player.startingStack - (committed[v.player.seatIndex] ?? 0);
            if (shortestVillainRem == null || rem < shortestVillainRem) {
              shortestVillainRem = rem;
            }
          }
          final effStack =
              shortestVillainRem == null ? 0 : min(heroRem, shortestVillainRem);
          if (effStack > 0) {
            spr = effStack / potBefore;
            sprHeadsUp = simVillains.length == 1;
            reqStackOff = sprHeadsUp ? requiredEquityToStackOff(spr) : null;
          }
        }
        streetResults.add(StreetEquityCheck(
          street: street.street,
          heroEquity: result.equity[0],
          boardSoFar: [...boardNames],
          villainCount: simVillains.length,
          iterations: result.iterations,
          realizedEquity: realizedEq,
          realizedHandClass: realizedEq != null ? hc : null,
          heroInPosition: realizedEq != null ? heroIp : null,
          spr: spr,
          reqStackOffEquity: reqStackOff,
          sprIsHeadsUp: sprHeadsUp,
          heroFacing: street.street == Street.preflop
              ? null
              : _heroFacing(street, hero.seatIndex, potBefore),
          betHeroFaced: street.street == Street.preflop
              ? null
              : _betHeroFaced(street, hero.seatIndex),
          // Field MDF only matters multiway (heads-up the pot-odds FACT governs).
          multiwayFieldMdf: (street.street != Street.preflop &&
                  simVillains.length > 1)
              ? _multiwayFieldMdf(street, hero.seatIndex, potBefore)
              : null,
        ));
      }
    }

    // Folds on this street take effect from the next street on.
    for (final a in street.actions) {
      if (a.type == ActionType.fold) foldedSeats.add(a.seat);
    }

    // Advance the pot + per-seat committed totals so the next street's
    // bet-sizing and SPR are measured against this street's action.
    final streetMax = <int, int>{};
    for (final a in street.actions) {
      final amt = a.amount ?? 0;
      if (amt > (streetMax[a.seat] ?? 0)) streetMax[a.seat] = amt;
    }
    streetMax.forEach(
        (seat, amt) => committed[seat] = (committed[seat] ?? 0) + amt);
    potBefore += streetMax.values.fold(0, (s, v) => s + v);
  }

  if (streetResults.isEmpty) return null;

  return HandEquityCheck(
    streets: streetResults,
    villains: [
      for (final v in modeled.where((v) => v.trail.isNotEmpty))
        VillainModel(
          name: v.player.name,
          position: v.position,
          usedExactCards: v.exactCards.isNotEmpty,
          appliedTags: [for (final t in v.tags) t],
          rangeTrail: v.trail,
        ),
    ],
    basedOnSynthesizedAction: hand.isQuickEntry,
    scenarioKey: scenarioKey,
  );
}
