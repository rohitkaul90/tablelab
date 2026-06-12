import 'dart:math';

import '../equity/gto_ranges.dart';
import '../models/hand_model.dart';

/// What hero was facing at the decision point.
///
/// `unopened`/`limp`/`openRaise`/`threeBet`/`fourBetPlus` are preflop
/// situations; `checkedTo`/`bet`/`raise` are postflop; `allIn` applies to any
/// street.
enum QuickFacing {
  unopened,
  limp,
  openRaise,
  threeBet,
  fourBetPlus,
  checkedTo,
  bet,
  raise,
  allIn,
}

enum QuickHeroAction { fold, check, call, bet, raise, allIn }

enum QuickResult { won, lost, chopped }

/// How the preflop pot was built when the decision came later. `auto` infers
/// it from hero's hand (GTO preset charts) and the stated pot size.
enum QuickPotType { auto, limped, singleRaised, threeBet, fourBet }

/// Everything the Quick Hand form collects. Sizes/amounts are in big blinds
/// (the natural unit mid-session); blinds themselves are in chips, matching
/// [TableSetup].
class QuickHandInput {
  final List<String> heroCards; // exactly 2, 'As' notation
  final int numSeats; // 2–9
  final String positionLabel; // member of TableSetup.positionLabels(numSeats)
  final int smallBlind;
  final int bigBlind;
  final Street decisionStreet;
  final List<String> boardCards; // [] or cumulative 3/4/5 cards
  final QuickFacing facing;
  final QuickHeroAction heroAction;
  final QuickPotType potType;
  final double? facingSizeBb;
  final double? heroSizeBb;
  final double? potBeforeBb; // pot entering the decision street
  final double? effStackBb;
  final QuickResult? result;
  final double? resultAmountBb;
  final String? userNote;
  final bool isTournament;
  final String? tournamentStage;
  final int? ante;

  const QuickHandInput({
    required this.heroCards,
    required this.numSeats,
    required this.positionLabel,
    required this.smallBlind,
    required this.bigBlind,
    required this.decisionStreet,
    this.boardCards = const [],
    required this.facing,
    required this.heroAction,
    this.potType = QuickPotType.auto,
    this.facingSizeBb,
    this.heroSizeBb,
    this.potBeforeBb,
    this.effStackBb,
    this.result,
    this.resultAmountBb,
    this.userNote,
    this.isTournament = false,
    this.tournamentStage,
    this.ante,
  });
}

/// The PokerHand-shaped pieces a quick entry produces; pass straight into
/// `HandService.saveHand(..., isQuickEntry: true)`.
class QuickHandSynthesis {
  final TableSetup tableSetup;
  final List<HandPlayer> players;
  final List<StreetData> streets;
  final String notes;

  const QuickHandSynthesis({
    required this.tableSetup,
    required this.players,
    required this.streets,
    required this.notes,
  });
}

/// 'As' + 'Kd' → 'AKo'; 'As' + 'Ks' → 'AKs'; 'As' + 'Ad' → 'AA'.
String quickHandNotation(List<String> cards) {
  const order = 'AKQJT98765432';
  final r1 = cards[0][0].toUpperCase();
  final r2 = cards[1][0].toUpperCase();
  if (r1 == r2) return '$r1$r2';
  final hi = order.indexOf(r1) < order.indexOf(r2) ? r1 : r2;
  final lo = hi == r1 ? r2 : r1;
  final suited =
      cards[0][cards[0].length - 1].toLowerCase() ==
          cards[1][cards[1].length - 1].toLowerCase();
  return '$hi$lo${suited ? 's' : 'o'}';
}

// ── chart classification ──────────────────────────────────────────────────────

final Map<String, Set<String>> _presetByKey = {
  for (final p in gtoPresets) p.key: p.hands,
};

bool _inChart(String? key, String hand) =>
    key != null && (_presetByKey[key]?.contains(hand) ?? false);

/// Hero's seat class for response-chart lookup.
String _posClass(String label) =>
    label == 'BB' ? 'bb' : (label == 'SB' ? 'sb' : 'ip');

/// When the villain is the opener, hero-in-the-blinds faces a late open (we
/// seat the villain on the button); hero in position faces an early open (we
/// seat the villain UTG).
String _openerBucket(String posClass) => posClass == 'ip' ? 'early' : 'late';

String? _rfiKey(String label, bool trn) {
  const map = {
    'UTG': 'utg', 'UTG+1': 'utg1', 'UTG+2': 'utg2', 'MP': 'mp',
    'HJ': 'hj', 'CO': 'co', 'BTN': 'btn', 'SB': 'sb',
  };
  final pos = map[label];
  if (pos == null) return null; // BB (and exotic labels) never open-raise
  return '${trn ? 'trn' : 'cash'}_rfi_$pos';
}

String _call3BetKey(String posClass, bool trn) => trn
    ? 'trn_call_3b'
    : (posClass == 'ip' ? 'cash_call_3b_ip' : 'cash_call_3b_oop');

String? _threeBetKey(String posClass, String bucket, bool trn) {
  if (trn) {
    return switch ((posClass, bucket)) {
      ('bb', 'late') => 'trn_3b_bb_vs_btn',
      ('bb', _) => 'trn_3b_bb_vs_early',
      ('sb', _) => 'trn_3b_sb_vs_late',
      ('ip', 'early') => 'trn_3b_ip_vs_early',
      ('ip', _) => 'trn_3b_btn_vs_co',
      _ => null,
    };
  }
  return switch ((posClass, bucket)) {
    ('bb', 'early') => 'cash_3b_bb_vs_utg',
    ('bb', 'middle') => 'cash_3b_bb_vs_co',
    ('bb', 'late') => 'cash_3b_bb_vs_btn',
    ('sb', 'early') => 'cash_3b_sb_vs_early',
    ('sb', 'middle') => 'cash_3b_sb_vs_middle',
    ('sb', 'late') => 'cash_3b_sb_vs_btn',
    ('ip', 'early') => 'cash_3b_ip_vs_early',
    ('ip', _) => 'cash_3b_btn_vs_co',
    _ => null,
  };
}

String _fourBetKey(bool trn) => trn ? 'trn_4b_value' : 'cash_4b_value';

// ── preflop story ─────────────────────────────────────────────────────────────

/// The synthesized route to the decision street: who drove the pot and how.
class _PreflopStory {
  final QuickPotType potType; // never auto
  final bool heroIsAggressor; // the last preflop raiser
  final bool heroLimpFirst; // hero limped before the villain's raise
  const _PreflopStory(this.potType, this.heroIsAggressor,
      {this.heroLimpFirst = false});

  String describe() {
    switch (potType) {
      case QuickPotType.limped:
        return 'limped pot';
      case QuickPotType.singleRaised:
        if (heroLimpFirst) return 'Hero limped, Villain raised, Hero called';
        return heroIsAggressor
            ? 'single-raised pot — Hero opened, Villain called'
            : 'single-raised pot — Villain opened, Hero called';
      case QuickPotType.threeBet:
        return heroIsAggressor
            ? '3-bet pot — Villain opened, Hero 3-bet, Villain called'
            : '3-bet pot — Hero opened, Villain 3-bet, Hero called';
      case QuickPotType.fourBet:
        return heroIsAggressor
            ? '4-bet pot — Hero opened, Villain 3-bet, Hero 4-bet, Villain called'
            : '4-bet pot — Villain opened, Hero 3-bet, Villain 4-bet, Hero called';
      case QuickPotType.auto:
        return '';
    }
  }
}

// Matched preflop contribution windows per pot type, in bb (per player).
const _matchedDefault = {
  QuickPotType.limped: 1.0,
  QuickPotType.singleRaised: 2.5,
  QuickPotType.threeBet: 9.0,
  QuickPotType.fourBet: 22.0,
};
const _matchedMin = {
  QuickPotType.limped: 1.0,
  QuickPotType.singleRaised: 2.0,
  QuickPotType.threeBet: 7.0,
  QuickPotType.fourBet: 18.0,
};
const _matchedMax = {
  QuickPotType.limped: 1.0,
  QuickPotType.singleRaised: 6.0,
  QuickPotType.threeBet: 20.0,
  QuickPotType.fourBet: 60.0,
};

// An intermediate street multiplies the pot by at most 4 (a 1.5-pot bet,
// called) and at least 1 (checked through).
const _maxStreetGrowth = 4.0;

bool _typeCanReach(QuickPotType t, double target, int nStreets) =>
    2 * _matchedMin[t]! <= target &&
    target <= 2 * _matchedMax[t]! * pow(_maxStreetGrowth, nStreets);

QuickPotType _inferPotType(
    double? targetBb, int nStreets, bool heroWould3Bet) {
  if (targetBb == null) {
    return heroWould3Bet ? QuickPotType.threeBet : QuickPotType.singleRaised;
  }
  if (targetBb < 2 * _matchedMin[QuickPotType.singleRaised]!) {
    return QuickPotType.limped;
  }
  final srpReaches =
      _typeCanReach(QuickPotType.singleRaised, targetBb, nStreets);
  final threeBetReaches =
      _typeCanReach(QuickPotType.threeBet, targetBb, nStreets);
  // A 3-bet hand in a 3-bet-sized pot is the more plausible story than a
  // single-raised pot inflated by huge bets.
  if (heroWould3Bet && threeBetReaches && targetBb >= 14) {
    return QuickPotType.threeBet;
  }
  if (srpReaches) return QuickPotType.singleRaised;
  if (threeBetReaches) return QuickPotType.threeBet;
  return QuickPotType.fourBet;
}

// ── synthesis ─────────────────────────────────────────────────────────────────

/// Expands a single recorded decision into a minimal but well-formed
/// [PokerHand] structure: two players (Hero + a stand-in Villain), one
/// street per street reached, and a chart-informed preflop line whose pot
/// reconciles exactly with the user's stated "pot entering this street".
///
/// Invariant (the replayer hard-crashes otherwise): every emitted action's
/// seat belongs to one of the two players. Never emit an action for an
/// unpopulated seat.
///
/// The synthesized actions are plausible scaffolding, never ground truth —
/// the [notes] context line states what was assumed and instructs the AI to
/// evaluate only the recorded decision.
QuickHandSynthesis synthesizeQuickHand(QuickHandInput input) {
  final labels = TableSetup.positionLabels(input.numSeats);
  final heroSeat = labels.indexOf(input.positionLabel);
  if (heroSeat < 0) {
    throw ArgumentError(
        'Unknown position "${input.positionLabel}" for ${input.numSeats} seats');
  }

  // Button at seat 0 makes positionName(seat) == labels[seat], so the
  // position filter resolves the chosen label with no extra bookkeeping.
  final setup = TableSetup(
    numSeats: input.numSeats,
    buttonSeat: 0,
    heroSeat: heroSeat,
    smallBlind: input.smallBlind,
    bigBlind: input.bigBlind,
    ante: input.isTournament ? input.ante : null,
  );

  final isPreflopDecision = input.decisionStreet == Street.preflop;
  final hand = quickHandNotation(input.heroCards);
  final posClass = _posClass(input.positionLabel);
  final bucket = _openerBucket(posClass);
  final trn = input.isTournament;

  final heroCanOpen = _inChart(_rfiKey(input.positionLabel, trn), hand);
  final heroWould3Bet = _inChart(_threeBetKey(posClass, bucket, trn), hand) ||
      _inChart(_fourBetKey(trn), hand);

  // ── story + villain seat ────────────────────────────────────────────────
  final nIntermediate =
      isPreflopDecision ? 0 : input.decisionStreet.index - 1;
  final resolvedType = isPreflopDecision
      ? QuickPotType.singleRaised // unused for preflop decisions
      : (input.potType == QuickPotType.auto
          ? _inferPotType(input.potBeforeBb, nIntermediate, heroWould3Bet)
          : input.potType);

  var story = _buildStory(resolvedType, heroCanOpen, heroWould3Bet,
      _inChart(_fourBetKey(trn), hand),
      _inChart(_call3BetKey(posClass, trn), hand), posClass);

  // The villain's seat must make the story's order of action possible.
  final (villainSeat, limpCall) = _villainSeat(
      setup: setup,
      heroSeat: heroSeat,
      story: story,
      isPreflopDecision: isPreflopDecision);
  if (limpCall) {
    story = _PreflopStory(story.potType, false, heroLimpFirst: true);
  }

  final stackChips = _bbToChips(input.effStackBb ?? 100, input.bigBlind);
  final players = [
    HandPlayer(
      seatIndex: heroSeat,
      name: 'Hero',
      startingStack: stackChips,
      isHero: true,
      holeCards: input.heroCards,
    ),
    HandPlayer(
      seatIndex: villainSeat,
      name: 'Villain',
      startingStack: stackChips,
    ),
  ];
  final occupied = {heroSeat, villainSeat};
  final effStackBb = input.effStackBb ?? 100;

  // Track each player's cumulative prior-street contribution (bb) so all-in
  // amounts (street totals) reflect the remaining stack.
  final priorBb = {heroSeat: 0.0, villainSeat: 0.0};

  // ── preflop scaffolding ─────────────────────────────────────────────────
  final preflopActions = <HandAction>[];
  for (final seat in [setup.sbSeat, setup.bbSeat]) {
    if (!occupied.contains(seat)) continue;
    final amount = seat == setup.sbSeat ? input.smallBlind : input.bigBlind;
    preflopActions
        .add(HandAction(seat: seat, type: ActionType.post, amount: amount));
    priorBb[seat] = amount / input.bigBlind;
  }

  // Per-street bb amounts each player ends up contributing before the
  // decision street: matched preflop amount + intermediate-street bets.
  var matchedBb = 0.0;
  final intermediateBetsBb = <double>[]; // bet size per intermediate street
  if (!isPreflopDecision) {
    final target = input.potBeforeBb;
    matchedBb = _matchedDefault[resolvedType]!;
    if (target != null) {
      if (nIntermediate == 0) {
        matchedBb = (target / 2)
            .clamp(_matchedMin[resolvedType]!, _matchedMax[resolvedType]!)
            .toDouble();
      } else {
        var m = pow(target / (2 * matchedBb), 1 / nIntermediate).toDouble();
        if (m > _maxStreetGrowth || m < 1) {
          // Re-center the preflop size so the per-street growth is plausible.
          matchedBb = (target / (2 * pow(_maxStreetGrowth, nIntermediate)))
              .clamp(_matchedMin[resolvedType]!, _matchedMax[resolvedType]!)
              .toDouble();
          m = pow(target / (2 * matchedBb), 1 / nIntermediate)
              .clamp(1.0, _maxStreetGrowth)
              .toDouble();
        }
        var pot = 2 * matchedBb;
        for (var i = 0; i < nIntermediate; i++) {
          double bet;
          if (i == nIntermediate - 1) {
            // Last synthesized street reconciles the pot exactly.
            bet = max(0.0, (target - pot) / 2);
          } else {
            bet = pot * (m - 1) / 2;
          }
          // Never bet past the remaining effective stack.
          bet = min(bet, effStackBb - matchedBb -
              intermediateBetsBb.fold(0.0, (s, b) => s + b));
          intermediateBetsBb.add(max(0.0, bet));
          pot += 2 * intermediateBetsBb.last;
        }
      }
    }
    // Cap the preflop match at the effective stack.
    matchedBb = min(matchedBb, effStackBb);

    preflopActions.addAll(_preflopLineActions(
      story: story,
      heroSeat: heroSeat,
      villainSeat: villainSeat,
      matchedBb: matchedBb,
      bigBlind: input.bigBlind,
    ));
    // Both players' prior-street totals (preflop match + intermediate bets)
    // must be settled BEFORE the decision-street actions are computed — the
    // all-in amounts below are remaining-stack street totals.
    final intermediateTotal =
        intermediateBetsBb.fold(0.0, (s, b) => s + b);
    priorBb[heroSeat] =
        max(priorBb[heroSeat]!, matchedBb) + intermediateTotal;
    priorBb[villainSeat] =
        max(priorBb[villainSeat]!, matchedBb) + intermediateTotal;
  }

  // ── decision-street actions ─────────────────────────────────────────────
  final potAtDecisionBb = isPreflopDecision
      ? 0.0
      : (input.potBeforeBb ?? 2 * matchedBb);
  final decisionActions = <HandAction>[];
  double? villainAmountBb; // villain's facing-action street total

  double defaultBetBb() =>
      potAtDecisionBb > 0 ? potAtDecisionBb * 2 / 3 : 5.0;

  int chips(double bb) => _bbToChips(bb, input.bigBlind);

  switch (input.facing) {
    case QuickFacing.unopened:
      break;
    case QuickFacing.checkedTo:
      decisionActions
          .add(HandAction(seat: villainSeat, type: ActionType.check));
    case QuickFacing.limp:
      villainAmountBb = 1;
      decisionActions.add(HandAction(
          seat: villainSeat, type: ActionType.call, amount: chips(1)));
    case QuickFacing.openRaise:
      villainAmountBb = input.facingSizeBb ?? 2.5;
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.raise,
          amount: chips(villainAmountBb)));
    case QuickFacing.threeBet:
      villainAmountBb = input.facingSizeBb ?? 9;
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.raise,
          amount: chips(villainAmountBb)));
    case QuickFacing.fourBetPlus:
      villainAmountBb = input.facingSizeBb ?? 22;
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.raise,
          amount: chips(villainAmountBb)));
    case QuickFacing.bet:
      villainAmountBb = input.facingSizeBb ?? defaultBetBb();
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.raise,
          amount: chips(villainAmountBb),
          isOpeningBet: true));
    case QuickFacing.raise:
      villainAmountBb = input.facingSizeBb ?? defaultBetBb() * 3;
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.raise,
          amount: chips(villainAmountBb)));
    case QuickFacing.allIn:
      villainAmountBb = effStackBb - priorBb[villainSeat]!;
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.allIn,
          amount: chips(villainAmountBb),
          isAllIn: true));
  }

  switch (input.heroAction) {
    case QuickHeroAction.fold:
      decisionActions.add(HandAction(seat: heroSeat, type: ActionType.fold));
    case QuickHeroAction.check:
      decisionActions.add(HandAction(seat: heroSeat, type: ActionType.check));
    case QuickHeroAction.call:
      decisionActions.add(HandAction(
          seat: heroSeat,
          type: ActionType.call,
          amount: chips(villainAmountBb ?? 1)));
    case QuickHeroAction.bet:
      decisionActions.add(HandAction(
          seat: heroSeat,
          type: ActionType.raise,
          amount: chips(input.heroSizeBb ?? defaultBetBb()),
          isOpeningBet: true));
    case QuickHeroAction.raise:
      decisionActions.add(HandAction(
          seat: heroSeat,
          type: ActionType.raise,
          amount: chips(input.heroSizeBb ??
              (villainAmountBb != null ? villainAmountBb * 2.5 : 2.5))));
    case QuickHeroAction.allIn:
      decisionActions.add(HandAction(
          seat: heroSeat,
          type: ActionType.allIn,
          amount: chips(effStackBb - priorBb[heroSeat]!),
          isAllIn: true));
  }

  // ── streets ─────────────────────────────────────────────────────────────
  final reached =
      Street.values.takeWhile((s) => s.index <= input.decisionStreet.index);
  final board = input.boardCards;
  var intermediateIdx = 0;
  final streets = reached.map((street) {
    final community = switch (street) {
      Street.preflop => const <String>[],
      Street.flop => board.length >= 3 ? board.sublist(0, 3) : const <String>[],
      Street.turn => board.length >= 4 ? [board[3]] : const <String>[],
      Street.river => board.length >= 5 ? [board[4]] : const <String>[],
    };
    List<HandAction> actions;
    if (street == Street.preflop) {
      actions = isPreflopDecision
          ? [...preflopActions, ...decisionActions]
          : preflopActions;
    } else if (street == input.decisionStreet) {
      actions = decisionActions;
    } else {
      // Intermediate street: the preflop aggressor barrels, the other calls
      // (or both check when no growth is needed). priorBb was already
      // settled above — do not re-add here.
      final betBb = intermediateIdx < intermediateBetsBb.length
          ? intermediateBetsBb[intermediateIdx]
          : 0.0;
      intermediateIdx++;
      final bettor = story.heroIsAggressor ? heroSeat : villainSeat;
      final caller = story.heroIsAggressor ? villainSeat : heroSeat;
      if (betBb < 0.5) {
        actions = [
          HandAction(seat: caller, type: ActionType.check),
          HandAction(seat: bettor, type: ActionType.check),
        ];
      } else {
        actions = [
          HandAction(
              seat: bettor,
              type: ActionType.raise,
              amount: chips(betBb),
              isOpeningBet: true),
          HandAction(seat: caller, type: ActionType.call, amount: chips(betBb)),
        ];
      }
    }
    return StreetData(
        street: street, communityCards: community, actions: actions);
  }).toList();

  return QuickHandSynthesis(
    tableSetup: setup,
    players: players,
    streets: streets,
    notes: _buildNotes(input,
        story: isPreflopDecision ? null : story,
        potAtDecisionBb: isPreflopDecision ? null : potAtDecisionBb),
  );
}

_PreflopStory _buildStory(QuickPotType type, bool heroCanOpen,
    bool heroWould3Bet, bool heroWould4Bet, bool heroWouldCall3Bet,
    String posClass) {
  switch (type) {
    case QuickPotType.limped:
      return const _PreflopStory(QuickPotType.limped, false);
    case QuickPotType.singleRaised:
      // Hero is only ever the aggressor when the charts say this hand opens —
      // a junk hand is always the caller (or the limper), never the raiser.
      if (heroCanOpen && posClass != 'bb') {
        return const _PreflopStory(QuickPotType.singleRaised, true);
      }
      return const _PreflopStory(QuickPotType.singleRaised, false);
    case QuickPotType.threeBet:
      if (heroWould3Bet) {
        return const _PreflopStory(QuickPotType.threeBet, true);
      }
      if (heroCanOpen && heroWouldCall3Bet && posClass != 'bb') {
        // Hero opened, the villain 3-bet, hero called.
        return const _PreflopStory(QuickPotType.threeBet, false);
      }
      // Everything else in a 3-bet pot reads as a 3-bet (bluffs included) —
      // more plausible than open-calling a 3-bet with a hand no chart holds.
      return const _PreflopStory(QuickPotType.threeBet, true);
    case QuickPotType.fourBet:
      if (heroWould4Bet && heroCanOpen) {
        return const _PreflopStory(QuickPotType.fourBet, true);
      }
      return const _PreflopStory(QuickPotType.fourBet, false);
    case QuickPotType.auto:
      throw StateError('potType must be resolved before building the story');
  }
}

/// Picks the villain's seat so the synthesized order of action is possible
/// and never collides with the hero's seat. Also reports whether the line
/// must become a limp-call (hero is the first seat to act, so nobody could
/// have opened before him).
(int, bool) _villainSeat({
  required TableSetup setup,
  required int heroSeat,
  required _PreflopStory story,
  required bool isPreflopDecision,
}) {
  final bbSeat = setup.bbSeat;
  final btn = setup.buttonSeat;
  if (setup.numSeats == 2) {
    // Heads-up: the only other seat. The button acts first preflop, so a
    // villain-opened line vs a button hero is necessarily a limp-call.
    final heroOnButton = heroSeat == btn;
    final villainOpened = !isPreflopDecision &&
        story.potType == QuickPotType.singleRaised &&
        !story.heroIsAggressor;
    return ((heroSeat + 1) % 2, heroOnButton && villainOpened);
  }
  if (isPreflopDecision) {
    // The facing description carries the story; default to the BB (most
    // decisions are against the blinds), button if hero is the BB.
    return (heroSeat == bbSeat ? btn : bbSeat, false);
  }
  final heroIsBlind = heroSeat == setup.sbSeat || heroSeat == bbSeat;
  final villainOpened = switch (story.potType) {
    QuickPotType.limped => false,
    QuickPotType.singleRaised => !story.heroIsAggressor,
    // 3-bet pot: hero-as-3-bettor means the villain opened; hero-as-opener
    // means the villain 3-bet from the blinds.
    QuickPotType.threeBet => story.heroIsAggressor,
    // 4-bet pot: hero-as-4-bettor means HERO opened (villain 3-bet from the
    // blinds); villain-as-4-bettor means the villain opened.
    QuickPotType.fourBet => !story.heroIsAggressor,
    QuickPotType.auto => false,
  };
  if (!villainOpened) {
    // Villain is the defender / 3-bettor: the blinds work from any hero seat.
    return (heroSeat == bbSeat ? btn : bbSeat, false);
  }
  // Villain opened before hero acted.
  if (heroIsBlind) return (btn, false); // a late open vs hero's blind defense
  // First seat to act preflop is UTG (button + 3).
  final utg = setup.numSeats >= 4 ? (btn + 3) % setup.numSeats : btn;
  if (utg != heroSeat) return (utg, false);
  // Hero is the first seat to act — nobody opened before; the BB raising
  // hero's limp keeps the order of action valid (limp-call line).
  return (bbSeat, story.potType == QuickPotType.singleRaised);
}

List<HandAction> _preflopLineActions({
  required _PreflopStory story,
  required int heroSeat,
  required int villainSeat,
  required double matchedBb,
  required int bigBlind,
}) {
  int chips(double bb) => _bbToChips(bb, bigBlind);
  final aggressor = story.heroIsAggressor ? heroSeat : villainSeat;
  final caller = story.heroIsAggressor ? villainSeat : heroSeat;

  switch (story.potType) {
    case QuickPotType.limped:
      return [
        HandAction(seat: heroSeat, type: ActionType.call, amount: chips(1)),
        HandAction(seat: villainSeat, type: ActionType.check),
      ];
    case QuickPotType.singleRaised:
      final needsLimp = !story.heroIsAggressor && story.heroLimpFirst;
      return [
        if (needsLimp)
          HandAction(seat: heroSeat, type: ActionType.call, amount: chips(1)),
        HandAction(
            seat: aggressor, type: ActionType.raise, amount: chips(matchedBb)),
        HandAction(
            seat: caller, type: ActionType.call, amount: chips(matchedBb)),
      ];
    case QuickPotType.threeBet:
      // Opener's open, the 3-bet, the call. Open ≈ 28% of the 3-bet size.
      final openBb = max(2.0, matchedBb * 0.28);
      return [
        HandAction(
            seat: caller, type: ActionType.raise, amount: chips(openBb)),
        HandAction(
            seat: aggressor, type: ActionType.raise, amount: chips(matchedBb)),
        HandAction(
            seat: caller, type: ActionType.call, amount: chips(matchedBb)),
      ];
    case QuickPotType.fourBet:
      final threeBetBb = max(7.0, matchedBb * 0.4);
      final openBb = max(2.0, threeBetBb * 0.28);
      return [
        HandAction(
            seat: aggressor, type: ActionType.raise, amount: chips(openBb)),
        HandAction(
            seat: caller, type: ActionType.raise, amount: chips(threeBetBb)),
        HandAction(
            seat: aggressor, type: ActionType.raise, amount: chips(matchedBb)),
        HandAction(
            seat: caller, type: ActionType.call, amount: chips(matchedBb)),
      ];
    case QuickPotType.auto:
      throw StateError('potType must be resolved');
  }
}

int _bbToChips(double bb, int bigBlind) => (bb * bigBlind).round();

String _fmtBb(double bb) {
  final rounded = (bb * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}bb'
      : '${rounded}bb';
}

String _buildNotes(QuickHandInput input,
    {_PreflopStory? story, double? potAtDecisionBb}) {
  final facingDesc = switch (input.facing) {
    QuickFacing.unopened => 'an unopened pot',
    QuickFacing.limp => 'a limp',
    QuickFacing.openRaise =>
      'an open to ${_fmtBb(input.facingSizeBb ?? 2.5)}',
    QuickFacing.threeBet => input.facingSizeBb != null
        ? 'a 3-bet to ${_fmtBb(input.facingSizeBb!)}'
        : 'a 3-bet',
    QuickFacing.fourBetPlus => input.facingSizeBb != null
        ? 'a 4-bet+ to ${_fmtBb(input.facingSizeBb!)}'
        : 'a 4-bet or more',
    QuickFacing.checkedTo => 'a check',
    QuickFacing.bet => input.facingSizeBb != null
        ? 'a bet of ${_fmtBb(input.facingSizeBb!)}'
        : 'a bet',
    QuickFacing.raise => input.facingSizeBb != null
        ? 'a raise to ${_fmtBb(input.facingSizeBb!)}'
        : 'a raise',
    QuickFacing.allIn => 'an all-in',
  };

  final heroDesc = switch (input.heroAction) {
    QuickHeroAction.fold => 'folded',
    QuickHeroAction.check => 'checked',
    QuickHeroAction.call => 'called',
    QuickHeroAction.bet => input.heroSizeBb != null
        ? 'bet ${_fmtBb(input.heroSizeBb!)}'
        : 'bet',
    QuickHeroAction.raise => input.heroSizeBb != null
        ? 'raised to ${_fmtBb(input.heroSizeBb!)}'
        : 'raised',
    QuickHeroAction.allIn => 'went all-in',
  };

  final game = input.isTournament
      ? 'tournament${input.tournamentStage != null ? ' (${input.tournamentStage})' : ''}'
      : 'cash';
  final pot = potAtDecisionBb != null && potAtDecisionBb > 0
      ? ' into a pot of ~${_fmtBb(potAtDecisionBb)}'
      : '';
  final board = input.boardCards.isNotEmpty
      ? ' Board: ${input.boardCards.join(' ')}.'
      : '';

  final sb = StringBuffer()
    ..write('[Quick entry] Only ONE decision point was recorded; all other '
        'action in this hand is auto-generated scaffolding. Evaluate ONLY the '
        'recorded decision below — do NOT critique the play on any other '
        'street.\n')
    ..write('${input.numSeats}-max ${input.smallBlind}/${input.bigBlind} '
        '$game, Hero ${input.positionLabel} with '
        '${input.heroCards.join(' ')}, '
        '~${_fmtBb(input.effStackBb ?? 100)} effective.')
    ..write(board);

  if (story != null) {
    sb.write(' Assumed (not recorded): ${story.describe()}'
        '${potAtDecisionBb != null && potAtDecisionBb > 0 ? ', reaching ~${_fmtBb(potAtDecisionBb)} on the ${input.decisionStreet.label.toLowerCase()}' : ''}.');
  }

  sb.write(' RECORDED ${input.decisionStreet.label} decision: '
      'facing $facingDesc$pot; Hero $heroDesc.');

  if (input.result != null) {
    final amount = input.resultAmountBb != null
        ? ' ~${_fmtBb(input.resultAmountBb!)}'
        : '';
    sb.write(' Result: ${input.result!.name}$amount.');
  }

  final note = input.userNote?.trim();
  if (note != null && note.isNotEmpty) {
    sb.write('\n\n$note');
  }
  return sb.toString();
}
