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

import 'package:flutter/foundation.dart' show compute;

import '../models/hand_model.dart';
import '../models/player_read.dart';
import 'card.dart';
import 'chart_keys.dart';
import 'evaluator.dart';
import 'simulator.dart';

// ── Result types ──────────────────────────────────────────────────────────────

class StreetEquityCheck {
  final Street street;

  /// Hero's equity (0–1) entering this street, vs all modeled villains.
  final double heroEquity;
  final List<String> boardSoFar;
  final int villainCount;
  final int iterations;

  const StreetEquityCheck({
    required this.street,
    required this.heroEquity,
    required this.boardSoFar,
    required this.villainCount,
    required this.iterations,
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

  const HandEquityCheck({
    required this.streets,
    required this.villains,
    required this.basedOnSynthesizedAction,
  });
}

/// Renders a [HandEquityCheck] into deterministic `[FACT —]` lines for the
/// `analyze-hand` prompt — the equity the model must not contradict, plus the
/// range assumption behind it. Returns an empty list when there is nothing to
/// assert. These are computed on-device, never by the model.
List<String> equityCheckFacts(HandEquityCheck check) {
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
  return facts;
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
({double value, double bluff}) _keepFractions(_StreetAct act) => switch (act) {
      _StreetAct.allIn => (value: 0.18, bluff: 0.07),
      _StreetAct.raise => (value: 0.22, bluff: 0.09),
      _StreetAct.bet => (value: 0.30, bluff: 0.15),
      _StreetAct.call => (value: 0.65, bluff: 0.0),
      _ => (value: 1.0, bluff: 0.0),
    };

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
}) =>
    compute(_computeEquityCheckSync, _EquityArgs(hand, reads, iterations));

class _EquityArgs {
  final PokerHand hand;
  final List<PlayerRead> reads;
  final int iterations;
  const _EquityArgs(this.hand, this.reads, this.iterations);
}

HandEquityCheck? _computeEquityCheckSync(_EquityArgs args) {
  final hand = args.hand;
  final reads = args.reads;
  final iterations = args.iterations;

  final hero = hand.hero;
  final heroCards = hero?.holeCards;
  if (hero == null || heroCards == null || heroCards.length != 2) return null;
  final h1 = parseCard(heroCards[0]);
  final h2 = parseCard(heroCards[1]);
  if (h1 < 0 || h2 < 0) return null;

  final opponents = hand.players.where((p) => !p.isHero).toList();
  if (opponents.isEmpty) return null;

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

  // ── Walk the streets, narrowing and simulating ──────────────────────────
  final streetResults = <StreetEquityCheck>[];
  final boardSoFar = <int>[];
  final boardNames = <String>[];
  final foldedSeats = <int>{};

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
        final fr = _keepFractions(act);
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
          v.trail.add('${street.street.label}: ${_actLabel(act)} → kept top '
              '${(valueFrac * 100).round()}% of range');
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
          v.trail.add(bluffCount > 0
              ? '${street.street.label}: ${_actLabel(act)} → polarized: '
                  'top ${(valueFrac * 100).round()}% value + bottom '
                  '${(bluffCount / n * 100).round()}% bluffs'
              : '${street.street.label}: ${_actLabel(act)} → kept top '
                  '${(valueFrac * 100).round()}% value (no bluffs added)');
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
        );
        streetResults.add(StreetEquityCheck(
          street: street.street,
          heroEquity: result.equity[0],
          boardSoFar: [...boardNames],
          villainCount: simVillains.length,
          iterations: result.iterations,
        ));
      }
    }

    // Folds on this street take effect from the next street on.
    for (final a in street.actions) {
      if (a.type == ActionType.fold) foldedSeats.add(a.seat);
    }
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
  );
}
