// Localized display labels for the stable analytics keys in
// lib/utils/helpers.dart (bucket enums, weekday ints, game-type / venue /
// table-quality ids). Every function takes the `AppLocalizations` explicitly so
// it works outside a widget context (pure analytics code, unit tests via
// `lookupAppLocalizations`). Keys stay in the data layer; words stay here.
import 'package:intl/intl.dart';

import '../utils/helpers.dart';
import 'generated/app_localizations.dart';

String buyInBucketLabel(AppLocalizations l10n, BuyInBucket b, String sym) =>
    switch (b) {
      BuyInBucket.under50 => l10n.bucketBuyInUnder50(sym),
      BuyInBucket.from50to100 => l10n.bucketBuyIn50to100(sym),
      BuyInBucket.from100to200 => l10n.bucketBuyIn100to200(sym),
      BuyInBucket.from200to500 => l10n.bucketBuyIn200to500(sym),
      BuyInBucket.over500 => l10n.bucketBuyInOver500(sym),
    };

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
  final date = DateTime(2024, 1, weekday);
  try {
    return DateFormat.E(l10n.localeName).format(date);
  } on Object {
    // intl throws if the locale's symbols were never loaded
    // (initializeDateFormatting) — fall back to English rather than crash.
    return DateFormat.E('en_US').format(date);
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
