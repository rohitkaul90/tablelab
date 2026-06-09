import 'session_model.dart';

enum SessionResult { win, loss }

class SessionFilter {
  final String? gameType;
  // Multi-select: empty = no filter, otherwise the session must match one of them.
  final Set<String> stakes;
  final Set<String> locations;
  final String? dateFrom;
  final String? dateTo;
  final SessionResult? result;

  const SessionFilter({
    this.gameType,
    this.stakes = const {},
    this.locations = const {},
    this.dateFrom,
    this.dateTo,
    this.result,
  });

  bool get isEmpty =>
      gameType == null &&
      stakes.isEmpty &&
      locations.isEmpty &&
      dateFrom == null &&
      dateTo == null &&
      result == null;

  bool matches(SessionModel s) {
    if (gameType != null) {
      if (gameType == 'tournament') {
        if (s.gameType != 'tournament' && s.gameType != 'sit_and_go') return false;
      } else if (s.gameType != gameType) {
        return false;
      }
    }
    if (stakes.isNotEmpty && !stakes.contains(s.stakes)) return false;
    if (locations.isNotEmpty &&
        (s.location == null || !locations.contains(s.location))) {
      return false;
    }
    if (dateFrom != null && s.date.compareTo(dateFrom!) < 0) return false;
    if (dateTo != null && s.date.compareTo(dateTo!) > 0) return false;
    if (result == SessionResult.win && s.profitLoss <= 0) return false;
    if (result == SessionResult.loss && s.profitLoss > 0) return false;
    return true;
  }

  SessionFilter copyWith({
    Object? gameType = _sentinel,
    Set<String>? stakes,
    Set<String>? locations,
    Object? dateFrom = _sentinel,
    Object? dateTo = _sentinel,
    Object? result = _sentinel,
  }) {
    return SessionFilter(
      gameType:
          identical(gameType, _sentinel) ? this.gameType : gameType as String?,
      stakes: stakes ?? this.stakes,
      locations: locations ?? this.locations,
      dateFrom:
          identical(dateFrom, _sentinel) ? this.dateFrom : dateFrom as String?,
      dateTo: identical(dateTo, _sentinel) ? this.dateTo : dateTo as String?,
      result: identical(result, _sentinel) ? this.result : result as SessionResult?,
    );
  }
}

const _sentinel = Object();
