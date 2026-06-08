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
  });

  factory SessionModel.fromMap(Map<String, dynamic> map) {
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
    );
  }
}
