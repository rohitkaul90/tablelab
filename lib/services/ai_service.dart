import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/session_model.dart';
import '../models/ai_analysis_model.dart';
import '../models/player_read.dart';
import '../models/hand_model.dart';
import 'analytics_service.dart';
import 'supabase_retry.dart';

/// AI analysis usage within the rolling 24h rate-limit window.
class AiUsage {
  final int session;
  final int hand;
  final bool exempt;
  const AiUsage(
      {required this.session, required this.hand, required this.exempt});

  /// Tallies ai_usage_log rows (each carrying a `function_name`) into a usage
  /// summary. Pure function — unit-testable without Supabase.
  factory AiUsage.fromRows(List<Map<String, dynamic>> rows,
      {required bool exempt}) {
    var session = 0;
    var hand = 0;
    for (final r in rows) {
      if (r['function_name'] == 'analyze-session') {
        session++;
      } else if (r['function_name'] == 'analyze-hand') {
        hand++;
      }
    }
    return AiUsage(session: session, hand: hand, exempt: exempt);
  }
}

/// A failed AI Edge Function call, mapped to a user-facing message plus the
/// HTTP status so the UI can tell a daily-limit (429) / at-capacity (503) /
/// generic failure apart. `functions.invoke` **throws** `FunctionException` on
/// any non-2xx (functions_client ≥2.x), carrying the server's `{error: ...}`
/// body in `details` — so callers must catch it rather than read `res.status`.
class AiException implements Exception {
  final int status;
  final String message;

  /// True only when our Edge Function produced the `{error: ...}` body. A
  /// non-2xx WITHOUT that body is a gateway/transport error (Supabase platform
  /// rate-limit, cold-boot, etc.) — **not** the function's own daily-limit or
  /// at-capacity response — so its status must not be read as those semantics.
  final bool fromServer;

  const AiException({
    required this.status,
    required this.message,
    this.fromServer = true,
  });

  bool get isRateLimited => fromServer && status == 429;
  bool get isAtCapacity => fromServer && status == 503;

  /// Builds from a `FunctionException`'s `status` + `details`. Pure + testable
  /// (takes the primitives, not the exception object). When `details` carries
  /// our function's `{error: <text>}`, that message + status are authoritative.
  /// Otherwise it's a gateway/transport failure → generic + retryable, and the
  /// status is not interpreted as a daily-limit / capacity signal.
  factory AiException.fromResponse(int status, dynamic details) {
    final serverMsg = (details is Map && details['error'] is String)
        ? details['error'] as String
        : null;
    if (serverMsg == null) {
      return AiException(
        status: status,
        message: 'Analysis failed. Please try again.',
        fromServer: false,
      );
    }
    return AiException(status: status, message: serverMsg);
  }

  @override
  String toString() => 'AiException($status): $message';
}

class AiService {
  /// [client] is injectable for tests; production uses the global Supabase
  /// client, resolved lazily so the service can be constructed without an
  /// initialized Supabase instance.
  AiService([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  // Must match the Edge Function constants (analyze-session / analyze-hand).
  static const sessionDailyLimit = 5;
  static const handDailyLimit = 20;
  static const _exemptEmails = {'rhtk.1234@gmail.com'};

  /// Counts the user's AI analyses in the same rolling 24h window the Edge
  /// Functions use for rate-limiting. Cache hits don't log usage, so these
  /// counts equal what actually counts against the daily limit.
  Future<AiUsage> fetchUsageLast24h() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const AiUsage(session: 0, hand: 0, exempt: false);
    }
    final exempt = _exemptEmails.contains(user.email ?? '');
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    final rows = await withSupabaseRetry<List<Map<String, dynamic>>>(
      () async => await _client
          .from('ai_usage_log')
          .select('function_name')
          .eq('user_id', user.id)
          .gte('called_at', since),
    );
    return AiUsage.fromRows(rows, exempt: exempt);
  }

  Future<SessionAnalysis> analyzeSession(
    SessionModel session, {
    List<PokerHand> hands = const [],
    List<PlayerRead> reads = const [],
    bool forceRefresh = false,
  }) async {
    // Fire `requested` *before* invoke() so request→completed is a real funnel
    // (a 429/503 throws before `completed`, surfacing the drop-off).
    AnalyticsService.aiSessionAnalysisRequested();
    try {
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
      final analysis = SessionAnalysis.fromJson(res.data as Map<String, dynamic>);
      AnalyticsService.aiAnalysisCompleted(featureType: 'session');
      return analysis;
    } on FunctionException catch (e) {
      // invoke() throws on any non-2xx; the server's message is in
      // details['error'] (daily limit 429, at-capacity 503, else generic).
      if (e.status == 429) {
        AnalyticsService.aiRateLimitHit(featureType: 'session');
      } else {
        AnalyticsService.aiAnalysisFailed(
          featureType: 'session',
          reason: e.status == 503 ? 'at_capacity' : 'server_error',
        );
      }
      throw AiException.fromResponse(e.status, e.details);
    } catch (e) {
      // Timeout / offline / malformed response — not an HTTP status. Rethrow
      // unchanged so the caller's error handling is untouched.
      AnalyticsService.aiAnalysisFailed(
        featureType: 'session',
        reason: aiFailureReason(e),
      );
      rethrow;
    }
  }

  Future<HandCoachingAnalysis> analyzeHand(
    PokerHand hand, {
    List<PlayerRead> reads = const [],
    bool forceRefresh = false,
    List<String> equityFacts = const [],
  }) async {
    // Fire `requested` *before* invoke() so request→completed is a real funnel
    // (a 429/503 throws before `completed`, surfacing the drop-off).
    AnalyticsService.aiHandAnalysisRequested();
    try {
      final res = await _client.functions.invoke(
        'analyze-hand',
        body: {
          'hand': hand.toJson(),
          'reads': reads
              .map((r) => {'playerLabel': r.playerLabel, 'tags': r.tags})
              .toList(),
          'forceRefresh': forceRefresh,
          // Deterministic on-device equity, injected into the prompt as ground
          // truth so the coaching can't contradict the math (see analyze-hand).
          if (equityFacts.isNotEmpty) 'equityFacts': equityFacts,
        },
      );
      final analysis =
          HandCoachingAnalysis.fromJson(res.data as Map<String, dynamic>);
      AnalyticsService.aiAnalysisCompleted(featureType: 'hand');
      return analysis;
    } on FunctionException catch (e) {
      // invoke() throws on any non-2xx; the server's message is in
      // details['error'] (daily limit 429, at-capacity 503, else generic).
      if (e.status == 429) {
        AnalyticsService.aiRateLimitHit(featureType: 'hand');
      } else {
        AnalyticsService.aiAnalysisFailed(
          featureType: 'hand',
          reason: e.status == 503 ? 'at_capacity' : 'server_error',
        );
      }
      throw AiException.fromResponse(e.status, e.details);
    } catch (e) {
      // Timeout / offline / malformed response — not an HTTP status. Rethrow
      // unchanged so the caller's error handling is untouched.
      AnalyticsService.aiAnalysisFailed(
        featureType: 'hand',
        reason: aiFailureReason(e),
      );
      rethrow;
    }
  }

  /// Thumbs up/down on a cached hand analysis. [rating] is 1 (up) or -1
  /// (down); rows are scoped by user_id + hand_id (the cache key). No-op when
  /// the cache row is missing — feedback is best-effort.
  Future<void> rateHandAnalysis(String handId, int rating) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await withSupabaseRetry(
      () => _client
          .from('ai_hand_analyses')
          .update({
            'rating': rating,
            'rated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', user.id)
          .eq('hand_id', handId),
    );
    AnalyticsService.aiAnalysisRated(featureType: 'hand', rating: rating);
  }

  /// Thumbs up/down on a cached session analysis ([rating]: 1 or -1).
  Future<void> rateSessionAnalysis(String sessionId, int rating) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await withSupabaseRetry(
      () => _client
          .from('ai_analyses')
          .update({
            'rating': rating,
            'rated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', user.id)
          .eq('session_id', sessionId),
    );
    AnalyticsService.aiAnalysisRated(featureType: 'session', rating: rating);
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

/// Classifies a non-HTTP analyze failure (the generic `catch` in
/// analyzeSession/analyzeHand) into a coarse `ai_analysis_failed` reason.
/// Heuristic + string-based because the underlying type differs by platform
/// (dart:io SocketException on mobile, XHR errors on web, TimeoutException
/// from the function timeout). Returns 'timeout' | 'network' | 'unknown'.
@visibleForTesting
String aiFailureReason(Object e) {
  if (e is TimeoutException) return 'timeout';
  final s = e.toString().toLowerCase();
  if (s.contains('timeout') || s.contains('timed out')) return 'timeout';
  if (s.contains('socket') ||
      s.contains('network') ||
      s.contains('connection') ||
      s.contains('failed host lookup') ||
      s.contains('xmlhttprequest') ||
      s.contains('clientexception')) {
    return 'network';
  }
  return 'unknown';
}
