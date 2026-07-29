import '../models/session_model.dart';

/// Column headers for the sessions CSV/Excel export.
///
/// New fields are APPENDED (never inserted) so existing spreadsheets and
/// external consumers keyed on column position don't break. Keep this list in
/// lockstep with [sessionExportRow] — `session_export_test.dart` guards the
/// alignment — and mirror any importable additions in the TableLab preset in
/// `import_mapping_screen.dart` so an export→import round-trip stays lossless.
const List<String> kSessionExportHeaders = [
  'date',
  'game_type',
  'stakes',
  'buy_in',
  'cash_out',
  'prize_won',
  'profit_loss',
  'start_time',
  'end_time',
  'duration_minutes',
  'location',
  'notes',
  'rake_paid',
  'finish_position',
  'total_entrants',
  'table_quality',
  'currency',
  'country',
  'table_size',
  'hands_per_hour',
  'total_expenses',
  'net_after_expenses',
  'break_minutes',
  'buyin_count',
];

/// One export row for [s], aligned with [kSessionExportHeaders].
/// Nullable fields export as '' (blank), not 0 — blank means "not tracked".
List<dynamic> sessionExportRow(SessionModel s) => [
      s.date,
      s.gameType,
      s.stakes,
      s.buyIn,
      s.cashOut,
      s.prizeWon ?? '',
      s.profitLoss,
      s.startTime,
      s.endTime,
      s.durationMinutes,
      s.location ?? '',
      s.notes ?? '',
      s.rakePaid ?? '',
      s.finishPosition ?? '',
      s.totalEntrants ?? '',
      s.tableQuality ?? '',
      s.currency,
      s.country ?? '',
      s.tableSize ?? '',
      s.handsPerHour ?? '',
      s.totalExpenses,
      s.netAfterExpenses,
      s.breakMinutes ?? '',
      // Blank (not 0) for sessions predating the live recorder — no event
      // history means the rebuy count is unknown, not zero.
      s.buyinEvents.isEmpty ? '' : s.buyinEvents.length,
    ];
