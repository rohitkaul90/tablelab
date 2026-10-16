// Localized display labels for the stable analytics keys in
// lib/utils/helpers.dart (bucket enums, weekday ints, game-type / venue /
// table-quality ids). Every function takes the `AppLocalizations` explicitly so
// it works outside a widget context (pure analytics code, unit tests via
// `lookupAppLocalizations`). Keys stay in the data layer; words stay here.
import 'package:intl/intl.dart';

import '../utils/helpers.dart';
import 'generated/app_localizations.dart';

/// Label for a buy-in band, with the rounded [displayCurrency] edges from
/// `buyInBandEdges` ("€50–€100", "< ₹5,000") — the same edges the sessions
/// are classified against.
String buyInBucketLabel(
    AppLocalizations l10n, BuyInBucket b, String displayCurrency) {
  final edges = buyInBandEdges(displayCurrency);
  String edge(int i) => formatAmount(edges[i], displayCurrency);
  return switch (b) {
    BuyInBucket.under50 => l10n.bucketBuyInUnder(edge(0)),
    BuyInBucket.from50to100 => l10n.bucketBuyInRange(edge(0), edge(1)),
    BuyInBucket.from100to200 => l10n.bucketBuyInRange(edge(1), edge(2)),
    BuyInBucket.from200to500 => l10n.bucketBuyInRange(edge(2), edge(3)),
    BuyInBucket.over500 => l10n.bucketBuyInOver(edge(3)),
  };
}

String fieldSizeBucketLabel(AppLocalizations l10n, FieldSizeBucket b) =>
    switch (b) {
      FieldSizeBucket.small => l10n.bucketFieldSmall,
      FieldSizeBucket.medium => l10n.bucketFieldMedium,
      FieldSizeBucket.large => l10n.bucketFieldLarge,
      FieldSizeBucket.massive => l10n.bucketFieldMassive,
    };

/// `short` = the one-word form used inside recommendation sentences.
String timeOfDayBucketLabel(AppLocalizations l10n, TimeOfDayBucket b,
    {bool short = false}) {
  if (short) {
    return switch (b) {
      TimeOfDayBucket.morning => l10n.bucketTimeMorningShort,
      TimeOfDayBucket.afternoon => l10n.bucketTimeAfternoonShort,
      TimeOfDayBucket.evening => l10n.bucketTimeEveningShort,
      TimeOfDayBucket.lateNight => l10n.bucketTimeLateNightShort,
    };
  }
  return switch (b) {
    TimeOfDayBucket.morning => l10n.bucketTimeMorning,
    TimeOfDayBucket.afternoon => l10n.bucketTimeAfternoon,
    TimeOfDayBucket.evening => l10n.bucketTimeEvening,
    TimeOfDayBucket.lateNight => l10n.bucketTimeLateNight,
  };
}

String sessionLengthBucketLabel(AppLocalizations l10n, SessionLengthBucket b) =>
    switch (b) {
      SessionLengthBucket.under2h => l10n.bucketLengthUnder2h,
      SessionLengthBucket.from2to4h => l10n.bucketLength2to4h,
      SessionLengthBucket.from4to6h => l10n.bucketLength4to6h,
      SessionLengthBucket.over6h => l10n.bucketLengthOver6h,
    };

/// Abbreviated weekday name ("Mon", "lun.") for an ISO weekday 1–7 in the
/// language of [l10n] (intl's symbols, so no ARB keys are needed; the app
/// loads them via applyIntlLocale before any frame renders).
String weekdayShortLabel(AppLocalizations l10n, int weekday) {
  // 2024-01-01 is a Monday; offsetting from it yields any weekday.
  return safeDateFormat(
      (loc) => DateFormat.E(loc), l10n.localeName, DateTime(2024, 1, weekday));
}

/// Formats [d] with [build] in [locale], falling back to en_US when the
/// locale's date symbols were never loaded (ArgumentError, or intl's
/// unexported LocaleDataException). Other Errors still propagate.
String safeDateFormat(
    DateFormat Function(String locale) build, String locale, DateTime d) {
  try {
    return build(locale).format(d);
  } catch (e) {
    if (e is Error && e is! ArgumentError) rethrow;
    return build('en_US').format(d);
  }
}

/// Label for a game-type key from `gameTypeKey()` ('cash' | 'tournament');
/// any other raw value is shown as-is.
String gameTypeKeyLabel(AppLocalizations l10n, String key) => switch (key) {
      'cash' => l10n.gameTypeCash,
      'tournament' => l10n.gameTypeTournament,
      _ => key,
    };

String tableQualityKeyLabel(AppLocalizations l10n, int? quality) =>
    switch (quality) {
      1 => l10n.tableQuality1,
      2 => l10n.tableQuality2,
      3 => l10n.tableQuality3,
      4 => l10n.tableQuality4,
      5 => l10n.tableQuality5,
      _ => l10n.tableQualityNotRated,
    };

/// Label for a venue key ('live' | 'online').
String venueLabel(AppLocalizations l10n, String key) =>
    key == 'online' ? l10n.venueOnline : l10n.venueLive;

/// Display label for a persisted expense-category id (`kExpenseCategoryIds`
/// in session_model.dart). Ids are stored in the `expense_events` jsonb and
/// never change; only the label is localized. Unknown ids read as "Other".
String expenseCategoryLabel(AppLocalizations l10n, String id) => switch (id) {
      'tip' => l10n.expenseCategoryTip,
      'food' => l10n.expenseCategoryFood,
      'massage' => l10n.expenseCategoryMassage,
      'travel' => l10n.expenseCategoryTravel,
      _ => l10n.expenseCategoryOther,
    };

/// "+$25/hr" — a pre-formatted money amount per hour.
String perHour(AppLocalizations l10n, String amount) => l10n.statsPerHour(amount);

/// Formats [d] in the UI language (`Intl.defaultLocale`, kept in step with the
/// app language by applyIntlLocale) with the en_US fallback of
/// [safeDateFormat] — use for every display date, e.g.
/// `uiDate((l) => DateFormat.yMMMd(l), d)`.
String uiDate(DateFormat Function(String locale) build, DateTime d) =>
    safeDateFormat(build, Intl.defaultLocale ?? 'en_US', d);

/// Upper-cases the first character (for headers like "octubre de 2026",
/// which es/fr/it month skeletons render in lowercase).
String capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
