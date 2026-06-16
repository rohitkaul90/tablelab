/// A single buy-in event within a session (initial buy-in, a rebuy, or an
/// add-on), timestamped so the live recorder can show a running history.
/// Serialized into the `buyin_events` JSONB column.
class BuyinEvent {
  final double amount;
  final DateTime ts;
  final String kind; // 'buyin' | 'rebuy' | 'addon'

  const BuyinEvent({
    required this.amount,
    required this.ts,
    required this.kind,
  });

  factory BuyinEvent.fromJson(Map<String, dynamic> j) => BuyinEvent(
        amount: (j['amount'] as num).toDouble(),
        ts: DateTime.parse(j['ts'] as String),
        kind: (j['kind'] as String?) ?? 'buyin',
      );

  /// Lenient parse for stored data — returns null on a malformed entry instead
  /// of throwing, so one bad jsonb element can't fail the whole session fetch.
  static BuyinEvent? tryFrom(Map<String, dynamic> j) {
    try {
      return BuyinEvent.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'ts': ts.toIso8601String(),
        'kind': kind,
      };
}

/// Expense categories tracked per session. Kept SEPARATE from the poker result
/// (profit_loss) — the app shows a derived net-after-expenses so win-rate /
/// BB-100 / variance stay pure. `(value, label)` pairs; `value` is what's
/// persisted, keep it stable.
const List<(String, String)> kExpenseCategories = [
  ('tip', 'Tips / tokes'),
  ('food', 'Food & drink'),
  ('massage', 'Massage'),
  ('travel', 'Travel / trip'),
  ('other', 'Other'),
];

String expenseCategoryLabel(String value) =>
    kExpenseCategories.where((c) => c.$1 == value).map((c) => c.$2).firstOrNull ??
    'Other';

/// A single non-poker expense incurred during a session (tip, food, massage,
/// travel, …). Serialized into the `expense_events` JSONB column. Tracked
/// separately from buy-in/cash-out so it never distorts the poker result.
class ExpenseEvent {
  final double amount;
  final String category; // one of kExpenseCategories values
  final String? note;
  final DateTime ts;

  const ExpenseEvent({
    required this.amount,
    required this.category,
    this.note,
    required this.ts,
  });

  factory ExpenseEvent.fromJson(Map<String, dynamic> j) => ExpenseEvent(
        amount: (j['amount'] as num).toDouble(),
        category: (j['category'] as String?) ?? 'other',
        note: j['note'] as String?,
        ts: DateTime.parse(j['ts'] as String),
      );

  /// Lenient parse for stored data — returns null on a malformed entry instead
  /// of throwing, so one bad jsonb element can't fail the whole session fetch.
  static ExpenseEvent? tryFrom(Map<String, dynamic> j) {
    try {
      return ExpenseEvent.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'category': category,
        if (note != null && note!.isNotEmpty) 'note': note,
        'ts': ts.toIso8601String(),
      };
}

class SessionModel {
  final String id;
  final String date;
  final String stakes;
  final String gameType;
  final double buyIn;
  final double cashOut;
  final double profitLoss;
  final String startTime;
  final String endTime;
  final int durationMinutes;
  final String? location;
  final String? notes;
  final String createdAt;
  final double? rakePaid;
  final int? finishPosition;
  final int? totalEntrants;
  final double? prizeWon;
  final int? tableQuality;
  final String currency;
  final int? handsPerHour;
  final String? country;
  final int? tableSize;

  // ── Live session recorder fields ──────────────────────────────────────────
  /// 'completed' (the default for every historically logged session) or 'live'
  /// while a session is still being played and recorded in real time.
  final String status;

  /// Full sit-down timestamp — the running-clock anchor. Lets the elapsed time
  /// be recomputed correctly even after the app is killed and relaunched.
  final DateTime? startedAt;

  /// Timestamped buy-in / rebuy / add-on history. `buyIn` stays the running sum
  /// of these amounts (so stats and back-compat keep working).
  final List<BuyinEvent> buyinEvents;

  /// Last-entered current stack while live; feeds the live net estimate.
  final double? currentStack;

  /// Non-poker expenses (tips, food, massage, travel, …) tracked separately
  /// from the poker result.
  final List<ExpenseEvent> expenseEvents;

  /// Minutes spent on break. `durationMinutes` stays the PLAYED time (gross −
  /// breaks); this is kept as metadata / "time at table" reconstruction.
  final int? breakMinutes;

  /// Set while a live session is paused (null otherwise) — the break clock
  /// anchor, so a pause survives an app kill.
  final DateTime? breakStartedAt;

  const SessionModel({
    required this.id,
    required this.date,
    required this.stakes,
    required this.gameType,
    required this.buyIn,
    required this.cashOut,
    required this.profitLoss,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.location,
    this.notes,
    required this.createdAt,
    this.rakePaid,
    this.finishPosition,
    this.totalEntrants,
    this.prizeWon,
    this.tableQuality,
    required this.currency,
    this.handsPerHour,
    this.country,
    this.tableSize,
    this.status = 'completed',
    this.startedAt,
    this.buyinEvents = const [],
    this.currentStack,
    this.expenseEvents = const [],
    this.breakMinutes,
    this.breakStartedAt,
  });

  /// True while the session is still being recorded live (not yet finalized).
  bool get isLive => status == 'live';

  /// True while a live session is currently paused on a break.
  bool get isOnBreak => breakStartedAt != null;

  /// Total bought in across all events; falls back to the `buyIn` column for
  /// sessions that predate the live recorder (no events recorded).
  double get totalBuyIn => buyinEvents.isEmpty
      ? buyIn
      : buyinEvents.fold(0.0, (sum, e) => sum + e.amount);

  /// Total non-poker expenses logged for this session.
  double get totalExpenses =>
      expenseEvents.fold(0.0, (sum, e) => sum + e.amount);

  /// The all-in result: poker profit minus expenses. Equals [profitLoss] when
  /// no expenses were logged, so it's safe to show everywhere.
  double get netAfterExpenses => profitLoss - totalExpenses;

  factory SessionModel.fromMap(Map<String, dynamic> map) {
    final rawEvents = map['buyin_events'];
    final events = rawEvents is List
        ? rawEvents
            .whereType<Map>()
            .map((e) => BuyinEvent.tryFrom(Map<String, dynamic>.from(e)))
            .whereType<BuyinEvent>()
            .toList()
        : <BuyinEvent>[];
    final startedAtRaw = map['started_at'] as String?;
    final rawExpenses = map['expense_events'];
    final expenses = rawExpenses is List
        ? rawExpenses
            .whereType<Map>()
            .map((e) => ExpenseEvent.tryFrom(Map<String, dynamic>.from(e)))
            .whereType<ExpenseEvent>()
            .toList()
        : <ExpenseEvent>[];
    final breakStartedRaw = map['break_started_at'] as String?;
    return SessionModel(
      id: map['id'] as String,
      date: map['date'] as String,
      stakes: map['stakes'] as String,
      gameType: map['game_type'] as String,
      buyIn: (map['buy_in'] as num).toDouble(),
      cashOut: (map['cash_out'] as num).toDouble(),
      profitLoss: (map['profit_loss'] as num).toDouble(),
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      durationMinutes: map['duration_minutes'] as int,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String,
      rakePaid: (map['rake_paid'] as num?)?.toDouble(),
      finishPosition: map['finish_position'] as int?,
      totalEntrants: map['total_entrants'] as int?,
      prizeWon: (map['prize_won'] as num?)?.toDouble(),
      tableQuality: map['table_quality'] as int?,
      currency: (map['currency'] as String?) ?? 'CAD',
      handsPerHour: map['hands_per_hour'] as int?,
      country: map['country'] as String?,
      tableSize: map['table_size'] as int?,
      status: (map['status'] as String?) ?? 'completed',
      startedAt:
          startedAtRaw != null ? DateTime.tryParse(startedAtRaw) : null,
      buyinEvents: events,
      currentStack: (map['current_stack'] as num?)?.toDouble(),
      expenseEvents: expenses,
      breakMinutes: map['break_minutes'] as int?,
      breakStartedAt:
          breakStartedRaw != null ? DateTime.tryParse(breakStartedRaw) : null,
    );
  }
}
