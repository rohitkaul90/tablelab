import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart' show intlLocaleOf;
import '../l10n/labels.dart' show safeDateFormat, venueLabel;
import 'session_model.dart';
import '../data/poker_rooms.dart' show isOnlineSession;
import '../utils/helpers.dart' show mostRecentSession;
import '../widgets/game_type_filter.dart'
    show filterByGameTypes, gameTypeChipLabel;

/// The shared Stats-screen "Display Options" filter — ONE instance covers
/// every Stats tab. Covers the AppBar filter sheet: game type, currency, date
/// range (preset or a custom [dateRange]), country, venue, location. (Game
/// type moved INTO the sheet when the in-body pills were removed — the tabbed
/// factor pages have no body pill any more.)
class StatsFilter {
  final Set<String> gameTypes; // {'cash'} | {'tournament'} | {} = all
  final String? displayCurrency;
  final Set<String> country;
  final String? venue; // 'live' | 'online' | null
  final Set<String> location;
  final String? datePreset; // '1Y' | '6M' | '3M' | '1M' | null
  final DateTimeRange? dateRange; // custom range; takes precedence over preset

  const StatsFilter({
    this.gameTypes = const {},
    this.displayCurrency,
    this.country = const {},
    this.venue,
    this.location = const {},
    this.datePreset,
    this.dateRange,
  });

  /// Same filter with only the game-type dimension replaced — used by the
  /// Summary tab's in-body type shortcuts (comparison-card headers / the
  /// back-to-combined chip) so they never clobber the sheet's other filters.
  StatsFilter withGameTypes(Set<String> types) => StatsFilter(
        gameTypes: types,
        displayCurrency: displayCurrency,
        country: country,
        venue: venue,
        location: location,
        datePreset: datePreset,
        dateRange: dateRange,
      );

  /// True when anything at all is set (drives the AppBar filter badge).
  bool get isActive =>
      gameTypes.isNotEmpty ||
      displayCurrency != null ||
      country.isNotEmpty ||
      venue != null ||
      location.isNotEmpty ||
      datePreset != null ||
      dateRange != null;

  /// True when a filter narrows the *session set* (everything except currency,
  /// which only converts). Used to decide when an all-time figure (e.g. the
  /// bankroll line) would be misleading.
  bool get narrowsSessions =>
      gameTypes.isNotEmpty ||
      country.isNotEmpty ||
      venue != null ||
      location.isNotEmpty ||
      datePreset != null ||
      dateRange != null;

  /// Display currency precedence: explicit per-view filter → the user's home
  /// currency ([homeCurrency], from the profile) → most-recent session → CAD.
  String effectiveCurrency(List<SessionModel> sessions, {String? homeCurrency}) {
    if (displayCurrency != null) return displayCurrency!;
    // Empty string (e.g. a bad import / direct DB edit) means "no home
    // currency", not a currency code — fall through rather than return ''.
    if (homeCurrency != null && homeCurrency.isNotEmpty) return homeCurrency;
    return mostRecentSession(sessions)?.currency ?? 'CAD';
  }

  /// Applies every dimension to [sessions].
  List<SessionModel> apply(List<SessionModel> sessions) {
    // Shared predicate with the (flag-gated) Overview pills — never re-fork.
    var r = filterByGameTypes(sessions, gameTypes);

    if (dateRange != null) {
      final start = DateTime(
          dateRange!.start.year, dateRange!.start.month, dateRange!.start.day);
      final end = DateTime(dateRange!.end.year, dateRange!.end.month,
          dateRange!.end.day, 23, 59, 59);
      r = r.where((s) {
        final d = DateTime.tryParse(s.date);
        return d != null && !d.isBefore(start) && !d.isAfter(end);
      }).toList();
    } else if (datePreset != null) {
      final days = switch (datePreset!) {
        '1M' => 30,
        '3M' => 90,
        '6M' => 180,
        '1Y' => 365,
        _ => 0,
      };
      if (days > 0) {
        final cutoff = DateTime.now().subtract(Duration(days: days));
        r = r.where((s) {
          final d = DateTime.tryParse(s.date);
          return d != null && d.isAfter(cutoff);
        }).toList();
      }
    }

    if (country.isNotEmpty) {
      r = r.where((s) => country.contains(s.country)).toList();
    }
    if (venue == 'online') {
      r = r.where((s) => isOnlineSession(s.location)).toList();
    } else if (venue == 'live') {
      r = r.where((s) => !isOnlineSession(s.location)).toList();
    }
    if (location.isNotEmpty) {
      r = r
          .where((s) => s.location != null && location.contains(s.location))
          .toList();
    }
    return r;
  }

  // Month + day in the UI language (intl symbols are loaded by
  // applyIntlLocale before any frame renders): "Jan 5" / "5 janv.".
  static String _fmtDate(AppLocalizations l10n, DateTime d) =>
      safeDateFormat((loc) => DateFormat.MMMd(loc), intlLocaleOf(l10n), d);

  static String _fmtDateYear(AppLocalizations l10n, DateTime d) =>
      safeDateFormat((loc) => DateFormat.yMMMd(loc), intlLocaleOf(l10n), d);

  /// Short label for the active date filter, or null when "all time".
  String? dateLabel(AppLocalizations l10n) {
    if (dateRange != null) {
      return '${_fmtDate(l10n, dateRange!.start)} – '
          '${_fmtDate(l10n, dateRange!.end)}';
    }
    if (datePreset != null) return _presetLabel(l10n);
    return null;
  }

  /// Longer summary for the filter-sheet subtitle.
  String dateSummary(AppLocalizations l10n) {
    if (dateRange != null) {
      return '${_fmtDateYear(l10n, dateRange!.start)} – '
          '${_fmtDateYear(l10n, dateRange!.end)}';
    }
    return _presetLabel(l10n);
  }

  /// Localized name of the date preset ("Last 12 months", …); the raw
  /// '1Y'/'6M' codes are keys, never shown.
  String _presetLabel(AppLocalizations l10n) {
    return switch (datePreset) {
      '1Y' => l10n.statsDate1Year,
      '6M' => l10n.statsDate6Months,
      '3M' => l10n.statsDate3Months,
      '1M' => l10n.statsDate1Month,
      _ => l10n.statsDateAllTime,
    };
  }

  /// Read-only chips for the metric chart screen (sheet filters only — the
  /// caller appends the currency, and a per-type card cell its own type
  /// label, as needed).
  List<String> labels(AppLocalizations l10n) {
    final type = gameTypeChipLabel(l10n, gameTypes);
    final date = dateLabel(l10n);
    return [
      if (type != null) type,
      if (date != null) date,
      if (country.length == 1)
        country.first
      else if (country.length > 1)
        l10n.statsNCountries(country.length),
      if (venue != null) venueLabel(l10n, venue!),
      if (location.length == 1)
        location.first
      else if (location.length > 1)
        l10n.statsNLocations(location.length),
    ];
  }
}
