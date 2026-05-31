import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/session_model.dart';
import '../models/ai_analysis_model.dart';
import '../models/player_read.dart';
import '../models/hand_model.dart';
import 'analytics_service.dart';

class AiService {
  final _client = Supabase.instance.client;

  Future<SessionAnalysis> analyzeSession(
    SessionModel session, {
    List<PokerHand> hands = const [],
    List<PlayerRead> reads = const [],
    bool forceRefresh = false,
  }) async {
    final res = await _client.functions.invoke(
      'analyze-session',
      body: {
        'session': _sessionJson(session),
        'hands': hands.map((h) => h.toJson()).toList(),
        'reads': reads
            .map((r) => {'playerLabel': r.playerLabel, 'tags': r.tags})
            .toList(),
        'forceRefresh': forceRefresh,
      },
    );

    final data = res.data;
    if (data is Map<String, dynamic> && data.containsKey('error')) {
      if (res.status == 429) {
        AnalyticsService.aiRateLimitHit(featureType: 'session');
      } else {
        AnalyticsService.aiSessionAnalysisRequested();
      }
      throw Exception(data['error']);
    }

    AnalyticsService.aiSessionAnalysisRequested();
    return SessionAnalysis.fromJson(data as Map<String, dynamic>);
  }

  Future<HandCoachingAnalysis> analyzeHand(
    PokerHand hand, {
    List<PlayerRead> reads = const [],
    bool forceRefresh = false,
  }) async {
    final res = await _client.functions.invoke(
      'analyze-hand',
      body: {
        'hand': hand.toJson(),
        'reads': reads
            .map((r) => {'playerLabel': r.playerLabel, 'tags': r.tags})
            .toList(),
        'forceRefresh': forceRefresh,
      },
    );

    final data = res.data;
    if (data is Map<String, dynamic> && data.containsKey('error')) {
      if (res.status == 429) {
        AnalyticsService.aiRateLimitHit(featureType: 'hand');
      } else {
        AnalyticsService.aiHandAnalysisRequested();
      }
      throw Exception(data['error']);
    }

    AnalyticsService.aiHandAnalysisRequested();
    return HandCoachingAnalysis.fromJson(data as Map<String, dynamic>);
  }

  Map<String, dynamic> _sessionJson(SessionModel s) => {
        'id': s.id,
        'date': s.date,
        'stakes': s.stakes,
        'gameType': s.gameType,
        'buyIn': s.buyIn,
        'cashOut': s.cashOut,
        'profitLoss': s.profitLoss,
        'durationMinutes': s.durationMinutes,
        'startTime': s.startTime,
        'endTime': s.endTime,
        if (s.location != null) 'location': s.location,
        if (s.country != null) 'country': s.country,
        if (s.notes != null) 'notes': s.notes,
        if (s.rakePaid != null) 'rakePaid': s.rakePaid,
        if (s.tableQuality != null) 'tableQuality': s.tableQuality,
        if (s.handsPerHour != null) 'handsPerHour': s.handsPerHour,
        if (s.finishPosition != null) 'finishPosition': s.finishPosition,
        if (s.totalEntrants != null) 'totalEntrants': s.totalEntrants,
        if (s.prizeWon != null) 'prizeWon': s.prizeWon,
        'currency': s.currency,
      };
}
