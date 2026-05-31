class ProfileModel {
  final String id;
  final String? displayName;
  final String? phone;
  final String? homeCity;
  final String? preferredGame;
  final String? preferredStakes;
  final int? playingSince;
  final double? hourlyRateGoal;
  final double? startingBankroll;
  final String startingBankrollCurrency;
  final bool hasSeenOnboarding;

  const ProfileModel({
    required this.id,
    this.displayName,
    this.phone,
    this.homeCity,
    this.preferredGame,
    this.preferredStakes,
    this.playingSince,
    this.hourlyRateGoal,
    this.startingBankroll,
    this.startingBankrollCurrency = 'CAD',
    this.hasSeenOnboarding = false,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) => ProfileModel(
        id: json['id'] as String,
        displayName: json['display_name'] as String?,
        phone: json['phone'] as String?,
        homeCity: json['home_city'] as String?,
        preferredGame: json['preferred_game'] as String?,
        preferredStakes: json['preferred_stakes'] as String?,
        playingSince: json['playing_since'] as int?,
        hourlyRateGoal: (json['hourly_rate_goal'] as num?)?.toDouble(),
        startingBankroll: (json['starting_bankroll'] as num?)?.toDouble(),
        startingBankrollCurrency:
            (json['starting_bankroll_currency'] as String?) ?? 'CAD',
        hasSeenOnboarding:
            (json['has_seen_onboarding'] as bool?) ?? false,
      );

  Map<String, dynamic> toUpsert() => {
        'id': id,
        'display_name': displayName,
        'phone': phone,
        'home_city': homeCity,
        'preferred_game': preferredGame,
        'preferred_stakes': preferredStakes,
        'playing_since': playingSince,
        'hourly_rate_goal': hourlyRateGoal,
        'starting_bankroll': startingBankroll,
        'starting_bankroll_currency': startingBankrollCurrency,
        'has_seen_onboarding': hasSeenOnboarding,
        'updated_at': DateTime.now().toIso8601String(),
      };

  ProfileModel copyWith({
    String? displayName,
    String? phone,
    String? homeCity,
    String? preferredGame,
    bool clearPreferredGame = false,
    String? preferredStakes,
    int? playingSince,
    double? hourlyRateGoal,
    double? startingBankroll,
    bool clearStartingBankroll = false,
    String? startingBankrollCurrency,
  }) =>
      ProfileModel(
        id: id,
        displayName: displayName ?? this.displayName,
        phone: phone ?? this.phone,
        homeCity: homeCity ?? this.homeCity,
        preferredGame: clearPreferredGame ? null : (preferredGame ?? this.preferredGame),
        preferredStakes: preferredStakes ?? this.preferredStakes,
        playingSince: playingSince ?? this.playingSince,
        hourlyRateGoal: hourlyRateGoal ?? this.hourlyRateGoal,
        startingBankroll: clearStartingBankroll ? null : (startingBankroll ?? this.startingBankroll),
        startingBankrollCurrency: startingBankrollCurrency ?? this.startingBankrollCurrency,
        hasSeenOnboarding: hasSeenOnboarding,
      );
}
