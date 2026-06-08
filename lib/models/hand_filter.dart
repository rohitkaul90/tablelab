import 'hand_model.dart';

/// Stable key used to group/filter hands by stake (small/big blind). Ignores
/// straddle so e.g. 1/2 and 1/2-with-straddle group together.
String handStakesKey(PokerHand h) =>
    '${h.tableSetup.smallBlind}/${h.tableSetup.bigBlind}';

/// Hero's position label for a hand (button is seat 0 in recording, so this is
/// the hero's seat offset from the button).
String handHeroPosition(PokerHand h) =>
    h.tableSetup.positionName(h.tableSetup.heroSeat);

String _dateKey(DateTime d) {
  final l = d.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-'
      '${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')}';
}

/// Funnel filter for the Hands tab. All set criteria are AND-ed together
/// (mirrors [SessionFilter]). Pot size is measured in **big blinds** so a
/// threshold means the same level of significance across mixed stakes.
class HandFilter {
  /// 'cash' | 'tournament'
  final String? gameType;

  /// Stake key from [handStakesKey], e.g. '1/2'.
  final String? stakes;

  /// Minimum pot size in big blinds (e.g. 20, 50, 100).
  final int? minPotBb;

  /// 'Pre-flop' | 'Flop' | 'Turn' | 'River' (matches [PokerHand.streetReached]).
  final String? streetReached;

  /// Seat count, 2–9.
  final int? tableSize;

  /// Hero position label, e.g. 'BTN'.
  final String? heroPosition;

  final String? dateFrom; // 'yyyy-MM-dd', inclusive
  final String? dateTo; // 'yyyy-MM-dd', inclusive

  const HandFilter({
    this.gameType,
    this.stakes,
    this.minPotBb,
    this.streetReached,
    this.tableSize,
    this.heroPosition,
    this.dateFrom,
    this.dateTo,
  });

  bool get isEmpty =>
      gameType == null &&
      stakes == null &&
      minPotBb == null &&
      streetReached == null &&
      tableSize == null &&
      heroPosition == null &&
      dateFrom == null &&
      dateTo == null;

  bool matches(PokerHand h) {
    final setup = h.tableSetup;

    if (gameType == 'tournament' && !h.isTournament) return false;
    if (gameType == 'cash' && h.isTournament) return false;

    if (stakes != null && handStakesKey(h) != stakes) return false;

    if (minPotBb != null) {
      final bb = setup.bigBlind;
      if (bb <= 0 || h.finalPot / bb < minPotBb!) return false;
    }

    if (streetReached != null && h.streetReached != streetReached) return false;
    if (tableSize != null && setup.numSeats != tableSize) return false;
    if (heroPosition != null && handHeroPosition(h) != heroPosition) {
      return false;
    }

    final dateKey = _dateKey(h.playedAt);
    if (dateFrom != null && dateKey.compareTo(dateFrom!) < 0) return false;
    if (dateTo != null && dateKey.compareTo(dateTo!) > 0) return false;

    return true;
  }

  HandFilter copyWith({
    Object? gameType = _sentinel,
    Object? stakes = _sentinel,
    Object? minPotBb = _sentinel,
    Object? streetReached = _sentinel,
    Object? tableSize = _sentinel,
    Object? heroPosition = _sentinel,
    Object? dateFrom = _sentinel,
    Object? dateTo = _sentinel,
  }) {
    return HandFilter(
      gameType:
          identical(gameType, _sentinel) ? this.gameType : gameType as String?,
      stakes: identical(stakes, _sentinel) ? this.stakes : stakes as String?,
      minPotBb:
          identical(minPotBb, _sentinel) ? this.minPotBb : minPotBb as int?,
      streetReached: identical(streetReached, _sentinel)
          ? this.streetReached
          : streetReached as String?,
      tableSize:
          identical(tableSize, _sentinel) ? this.tableSize : tableSize as int?,
      heroPosition: identical(heroPosition, _sentinel)
          ? this.heroPosition
          : heroPosition as String?,
      dateFrom:
          identical(dateFrom, _sentinel) ? this.dateFrom : dateFrom as String?,
      dateTo: identical(dateTo, _sentinel) ? this.dateTo : dateTo as String?,
    );
  }
}

const _sentinel = Object();
