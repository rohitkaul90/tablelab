import 'package:intl/intl.dart';
import '../l10n/labels.dart' show uiDate, capitalizeFirst;

class TournamentListing {
  final String id;
  final String name;
  final String venue;
  final String city;
  final String country;
  final DateTime startDate;
  final DateTime? endDate;
  final double? buyIn;
  final String currency;
  final double? guarantee;
  final String? series;
  final String? url;
  final String? notes;

  const TournamentListing({
    required this.id,
    required this.name,
    required this.venue,
    required this.city,
    required this.country,
    required this.startDate,
    this.endDate,
    this.buyIn,
    required this.currency,
    this.guarantee,
    this.series,
    this.url,
    this.notes,
  });

  factory TournamentListing.fromMap(Map<String, dynamic> map) {
    return TournamentListing(
      id: map['id'] as String,
      name: map['name'] as String,
      venue: map['venue'] as String,
      city: map['city'] as String,
      country: map['country'] as String,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: map['end_date'] != null
          ? DateTime.parse(map['end_date'] as String)
          : null,
      buyIn: (map['buy_in'] as num?)?.toDouble(),
      currency: map['currency'] as String? ?? 'USD',
      guarantee: (map['guarantee'] as num?)?.toDouble(),
      series: map['series'] as String?,
      url: map['url'] as String?,
      notes: map['notes'] as String?,
    );
  }

  bool get isPast {
    final end = endDate ?? startDate;
    return end.isBefore(DateTime.now().subtract(const Duration(days: 1)));
  }

  bool get isOngoing {
    final now = DateTime.now();
    return startDate.isBefore(now) && !isPast;
  }

  String get monthKey =>
      capitalizeFirst(uiDate((l) => DateFormat.yMMMM(l), startDate));

  String get formattedDates {
    String md(DateTime d) => uiDate((l) => DateFormat.MMMd(l), d);
    if (endDate == null) return md(startDate);
    // Both ends in full: a "Oct 16–18" shortcut assumes month-before-day,
    // which only holds in English ("16 oct.–18" in French).
    return '${md(startDate)} – ${md(endDate!)}';
  }

  String get formattedBuyIn {
    if (buyIn == null) return 'N/A';
    return '${_currencySym(currency)}${_compactNumber(buyIn!)}';
  }

  String get formattedGuarantee {
    if (guarantee == null) return '';
    return 'GTD ${_currencySym(currency)}${_compactNumber(guarantee!)}';
  }

  static String _currencySym(String c) {
    switch (c) {
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'CAD': return 'CA\$';
      default: return '$c ';
    }
  }

  static String _compactNumber(double v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m % 1 == 0 ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
    }
    if (v >= 1000) {
      final k = v / 1000;
      return '${k % 1 == 0 ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
    }
    return v.toStringAsFixed(0);
  }
}
