import 'package:intl/intl.dart';
import '../models/session_model.dart';

int calcDurationMinutes(String startTime, String endTime) {
  final start = _timeToMinutes(startTime);
  final end = _timeToMinutes(endTime);
  if (start < 0 || end < 0) return 0;
  int diff = end - start;
  if (diff < 0) diff += 24 * 60;
  return diff;
}

int _timeToMinutes(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return -1;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return -1;
  return h * 60 + m;
}

String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

final _numFmt = NumberFormat('#,##0', 'en_US');

String formatPL(double amount, [String sym = '\$']) {
  final abs = amount.abs().round();
  return amount >= 0 ? '+$sym${_numFmt.format(abs)}' : '-$sym${_numFmt.format(abs)}';
}

String currencySymbol(String currency) {
  switch (currency) {
    case 'USD': return '\$';
    case 'CAD': return 'CA\$';
    case 'GBP': return '£';
    case 'EUR': return '€';
    case 'AUD': return 'A\$';
    case 'NZD': return 'NZ\$';
    case 'INR': return '₹';
    default: return '\$';
  }
}

String? currencyFromCountry(String? country) {
  if (country == null || country.isEmpty) return null;
  switch (country.toLowerCase()) {
    case 'canada': return 'CAD';
    case 'usa': case 'united states': case 'us': case 'online': return 'USD';
    case 'united kingdom': case 'uk': return 'GBP';
    case 'australia': return 'AUD';
    case 'new zealand': return 'NZD';
    case 'india': return 'INR';
    case 'france': case 'germany': case 'spain': case 'italy':
    case 'netherlands': case 'belgium': case 'czech republic':
    case 'monaco': case 'europe': return 'EUR';
    default: return null;
  }
}

String formatAmount(double amount, String currency) {
  return '${currencySymbol(currency)}${_numFmt.format(amount.round())}';
}

String formatPLWithCurrency(double amount, String currency) =>
    formatPL(amount, currencySymbol(currency));

double calcROI(double profitLoss, double buyIn) {
  if (buyIn <= 0) return 0;
  return profitLoss / buyIn * 100;
}

String formatROI(double roiPercent) {
  return '${roiPercent >= 0 ? '+' : ''}${roiPercent.toStringAsFixed(0)}%';
}

String tournamentBuyInBucket(double buyIn) {
  if (buyIn < 50) return '< \$50';
  if (buyIn < 100) return '\$50–\$100';
  if (buyIn < 200) return '\$100–\$200';
  if (buyIn < 500) return '\$200–\$500';
  return '> \$500';
}

String fieldSizeBucket(int? totalEntrants) {
  if (totalEntrants == null || totalEntrants <= 0) return '';
  if (totalEntrants < 50) return 'Small (<50)';
  if (totalEntrants < 200) return 'Medium (50–200)';
  if (totalEntrants < 500) return 'Large (200–500)';
  return 'Massive (500+)';
}

bool isTournamentType(String gameType) =>
    gameType == 'tournament' || gameType == 'sit_and_go';

/// A tournament session is ITM when either:
/// - prizeWon is explicitly recorded and > 0, OR
/// - prizeWon was not recorded (e.g. HUD imports) but profitLoss > 0,
///   meaning the player got back more than they put in.
bool isSessionItm(double? prizeWon, double profitLoss) =>
    prizeWon != null ? prizeWon > 0 : profitLoss > 0;

String gameTypeLabel(String gameType) {
  switch (gameType) {
    case 'cash': return 'Cash Game';
    case 'tournament': case 'sit_and_go': return 'Tournament';
    default: return gameType;
  }
}

String tableQualityLabel(int? quality) {
  switch (quality) {
    case 1: return 'Very Tough';
    case 2: return 'Tough';
    case 3: return 'Average';
    case 4: return 'Soft';
    case 5: return 'Very Soft';
    default: return 'Not rated';
  }
}

/// Friendly label for a table's player count (2 = heads-up … 9 = full ring).
/// Shared by hand recording, the session form, and session detail.
String tableSizeLabel(int n) => switch (n) {
      2 => 'Heads-up (2)',
      6 => '6-max',
      9 => '9-max (full ring)',
      _ => '$n-handed',
    };

String timeOfDayBucket(String startTime) {
  final hour = int.tryParse(startTime.split(':')[0]) ?? 0;
  if (hour >= 6 && hour < 12) return 'Morning (6am–12pm)';
  if (hour >= 12 && hour < 18) return 'Afternoon (12pm–6pm)';
  if (hour >= 18 && hour < 23) return 'Evening (6pm–11pm)';
  return 'Late Night (11pm–6am)';
}

String sessionLengthBucket(int minutes) {
  if (minutes < 120) return '< 2 hours';
  if (minutes < 240) return '2–4 hours';
  if (minutes < 360) return '4–6 hours';
  return '> 6 hours';
}

String dayOfWeekLabel(String date) {
  final dt = DateTime.tryParse(date) ?? DateTime.now();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[dt.weekday - 1];
}

String monthLabel(String date) {
  final dt = DateTime.tryParse(date) ?? DateTime.now();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.year}';
}

// ─── BB/100 ───────────────────────────────────────────────────────────────────

/// Parses the big-blind size from a stakes string like "1/2", "2/5", "$1/$2".
/// Returns null if the format is unrecognisable.
double? parseBBFromStakes(String stakes) {
  final clean = stakes.replaceAll(r'$', '').trim();
  final parts = clean.split('/');
  if (parts.length < 2) return null;
  return double.tryParse(parts[1].trim());
}

/// BB/100 across the given sessions.
///
/// Only includes cash sessions where both [handsPerHour] is set and the BB
/// can be parsed from [stakes].  Returns null when no qualifying data exists.
/// The result is dimensionless (profit expressed in BBs), so no currency
/// conversion is needed.
double? calcBB100(List<SessionModel> sessions) {
  double totalProfitBBs = 0;
  double totalHands = 0;
  for (final s in sessions) {
    if (s.gameType != 'cash') continue;
    final bb = parseBBFromStakes(s.stakes);
    if (bb == null || bb <= 0) continue;
    // Use recorded hands/hr if available, otherwise assume 25 (typical live default).
    final hph = s.handsPerHour ?? 25;
    final hands = hph * (s.durationMinutes / 60.0);
    if (hands <= 0) continue;
    totalProfitBBs += s.profitLoss / bb;
    totalHands += hands;
  }
  if (totalHands <= 0) return null;
  return totalProfitBBs / totalHands * 100;
}

String formatBB100(double bb100) {
  final sign = bb100 >= 0 ? '+' : '';
  return '$sign${bb100.round()}';
}

// ─── Currency Conversion ──────────────────────────────────────────────────────

// Approximate exchange rates (1 USD = X units). Updated May 2026.
const Map<String, double> _ratesPerUsd = {
  'USD': 1.0,
  'CAD': 1.38,
  'GBP': 0.78,
  'EUR': 0.92,
  'AUD': 1.59,
  'NZD': 1.73,
  'INR': 84.5,
};

/// Converts [amount] from [from] currency to [to] currency.
double convertCurrency(double amount, String from, String to) {
  if (from == to) return amount;
  final fromRate = _ratesPerUsd[from] ?? 1.0;
  final toRate = _ratesPerUsd[to] ?? 1.0;
  return amount / fromRate * toRate;
}

/// All currencies supported for display conversion.
final List<String> supportedDisplayCurrencies =
    (_ratesPerUsd.keys.toList()..sort());
