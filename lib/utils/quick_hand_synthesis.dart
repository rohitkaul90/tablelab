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

/// Expands a single recorded decision into a minimal but well-formed
/// [PokerHand] structure: two players (Hero + a stand-in Villain), one
/// street per street reached, synthesized posts/action so `finalPot`,
/// `streetReached`, the replayer, and the hand filters all behave.
///
/// Invariant (the replayer hard-crashes otherwise): every emitted action's
/// seat belongs to one of the two players. Never emit an action for an
/// unpopulated seat.
///
/// The synthesized actions are approximations; the [notes] context line is
/// the ground truth and is what the AI coaching reads.
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

  // Villain defaults to the BB seat (most decisions face the blinds); if hero
  // *is* the BB, the villain takes the button.
  final villainSeat = setup.bbSeat == heroSeat ? setup.buttonSeat : setup.bbSeat;
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

  // Track each player's largest prior-street contribution so all-in amounts
  // (street totals) reflect the remaining stack.
  final priorContrib = {heroSeat: 0, villainSeat: 0};

  // ── preflop scaffolding ───────────────────────────────────────────────────
  final preflopActions = <HandAction>[];
  for (final seat in [setup.sbSeat, setup.bbSeat]) {
    if (!occupied.contains(seat)) continue;
    final amount = seat == setup.sbSeat ? input.smallBlind : input.bigBlind;
    preflopActions.add(HandAction(seat: seat, type: ActionType.post, amount: amount));
    priorContrib[seat] = amount;
  }

  final isPreflopDecision = input.decisionStreet == Street.preflop;
  if (!isPreflopDecision && input.potBeforeBb != null) {
    // A matched raise/call pair whose street totals sum to ~the stated pot.
    final half = (input.potBeforeBb! * input.bigBlind / 2).round();
    preflopActions
      ..add(HandAction(seat: villainSeat, type: ActionType.raise, amount: half))
      ..add(HandAction(seat: heroSeat, type: ActionType.call, amount: half));
    priorContrib[villainSeat] = half;
    priorContrib[heroSeat] = half;
  }

  // ── decision-street actions ───────────────────────────────────────────────
  final decisionActions = <HandAction>[];
  int? villainAmount; // street total of the villain's facing action, chips

  int defaultBetChips() {
    final bb = input.potBeforeBb != null ? input.potBeforeBb! * 2 / 3 : 5.0;
    return _bbToChips(bb, input.bigBlind);
  }

  switch (input.facing) {
    case QuickFacing.unopened:
    case QuickFacing.checkedTo:
      if (input.facing == QuickFacing.checkedTo) {
        decisionActions
            .add(HandAction(seat: villainSeat, type: ActionType.check));
      }
    case QuickFacing.limp:
      villainAmount = input.bigBlind;
      decisionActions.add(HandAction(
          seat: villainSeat, type: ActionType.call, amount: villainAmount));
    case QuickFacing.openRaise:
      villainAmount = _bbToChips(input.facingSizeBb ?? 2.5, input.bigBlind);
      decisionActions.add(HandAction(
          seat: villainSeat, type: ActionType.raise, amount: villainAmount));
    case QuickFacing.threeBet:
      villainAmount = _bbToChips(input.facingSizeBb ?? 9, input.bigBlind);
      decisionActions.add(HandAction(
          seat: villainSeat, type: ActionType.raise, amount: villainAmount));
    case QuickFacing.fourBetPlus:
      villainAmount = _bbToChips(input.facingSizeBb ?? 22, input.bigBlind);
      decisionActions.add(HandAction(
          seat: villainSeat, type: ActionType.raise, amount: villainAmount));
    case QuickFacing.bet:
      villainAmount = input.facingSizeBb != null
          ? _bbToChips(input.facingSizeBb!, input.bigBlind)
          : defaultBetChips();
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.raise,
          amount: villainAmount,
          isOpeningBet: true));
    case QuickFacing.raise:
      villainAmount = input.facingSizeBb != null
          ? _bbToChips(input.facingSizeBb!, input.bigBlind)
          : defaultBetChips() * 3;
      decisionActions.add(HandAction(
          seat: villainSeat, type: ActionType.raise, amount: villainAmount));
    case QuickFacing.allIn:
      villainAmount = stackChips - priorContrib[villainSeat]!;
      decisionActions.add(HandAction(
          seat: villainSeat,
          type: ActionType.allIn,
          amount: villainAmount,
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
          amount: villainAmount ?? input.bigBlind));
    case QuickHeroAction.bet:
      decisionActions.add(HandAction(
          seat: heroSeat,
          type: ActionType.raise,
          amount: input.heroSizeBb != null
              ? _bbToChips(input.heroSizeBb!, input.bigBlind)
              : defaultBetChips(),
          isOpeningBet: true));
    case QuickHeroAction.raise:
      decisionActions.add(HandAction(
          seat: heroSeat,
          type: ActionType.raise,
          amount: input.heroSizeBb != null
              ? _bbToChips(input.heroSizeBb!, input.bigBlind)
              : (villainAmount != null
                  ? (villainAmount * 2.5).round()
                  : _bbToChips(2.5, input.bigBlind))));
    case QuickHeroAction.allIn:
      decisionActions.add(HandAction(
          seat: heroSeat,
          type: ActionType.allIn,
          amount: stackChips - priorContrib[heroSeat]!,
          isAllIn: true));
  }

  // ── streets ───────────────────────────────────────────────────────────────
  final reached =
      Street.values.takeWhile((s) => s.index <= input.decisionStreet.index);
  final board = input.boardCards;
  final streets = reached.map((street) {
    final community = switch (street) {
      Street.preflop => const <String>[],
      Street.flop => board.length >= 3 ? board.sublist(0, 3) : const <String>[],
      Street.turn => board.length >= 4 ? [board[3]] : const <String>[],
      Street.river => board.length >= 5 ? [board[4]] : const <String>[],
    };
    final actions = street == Street.preflop
        ? (isPreflopDecision
            ? [...preflopActions, ...decisionActions]
            : preflopActions)
        : (street == input.decisionStreet ? decisionActions : <HandAction>[]);
    return StreetData(street: street, communityCards: community, actions: actions);
  }).toList();

  return QuickHandSynthesis(
    tableSetup: setup,
    players: players,
    streets: streets,
    notes: _buildNotes(input),
  );
}

int _bbToChips(double bb, int bigBlind) => (bb * bigBlind).round();

String _fmtBb(double bb) =>
    bb == bb.roundToDouble() ? '${bb.round()}bb' : '${bb}bb';

String _buildNotes(QuickHandInput input) {
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
  final pot = input.potBeforeBb != null
      ? ' into a pot of ~${_fmtBb(input.potBeforeBb!)}'
      : '';
  final board = input.boardCards.isNotEmpty
      ? ' Board: ${input.boardCards.join(' ')}.'
      : '';

  final sb = StringBuffer()
    ..write('[Quick entry — single decision point, other action approximated] ')
    ..write('${input.numSeats}-max ${input.smallBlind}/${input.bigBlind} $game, ')
    ..write('Hero ${input.positionLabel} with ${input.heroCards.join(' ')}, ')
    ..write('~${_fmtBb(input.effStackBb ?? 100)} effective.')
    ..write(board)
    ..write(' ${input.decisionStreet.label} decision: '
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
