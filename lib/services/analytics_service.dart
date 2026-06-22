import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

// PostHog Flutter SDK supports Android, iOS, Web, macOS, Linux.
// Windows desktop is not supported — all calls are no-ops there.
bool get _analyticsSupported =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.windows;

class AnalyticsService {
  static Future<void> identify(String userId, {String? email}) async {
    if (!_analyticsSupported) return;
    await Posthog().identify(
      userId: userId,
      // PostHog's People page uses the `email` person property as the display
      // name — without it testers are unmatchable anonymous device IDs.
      userProperties: {if (email != null) 'email': email},
    );
  }

  static Future<void> reset() async {
    if (!_analyticsSupported) return;
    await Posthog().reset();
  }

  // ── Onboarding ──────────────────────────────────────────────────────────────

  static void onboardingCompleted() {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'onboarding_completed');
  }

  static void onboardingSkipped() {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'onboarding_skipped');
  }

  // ── Sessions ────────────────────────────────────────────────────────────────

  @visibleForTesting
  static Map<String, Object> sessionLoggedProps({
    required String gameType,
    required String currency,
    required bool hasNotes,
    required String source,
  }) =>
      {
        'game_type': gameType,
        'currency': currency,
        'has_notes': hasNotes,
        'source': source,
      };

  static void sessionLogged({
    required String gameType,
    required String currency,
    required bool hasNotes,
    required String source, // 'past' (manual form) or 'live' (finalized recorder)
  }) {
    if (!_analyticsSupported) return;
    Posthog().capture(
      eventName: 'session_logged',
      properties: sessionLoggedProps(
        gameType: gameType,
        currency: currency,
        hasNotes: hasNotes,
        source: source,
      ),
    );
  }

  @visibleForTesting
  static Map<String, Object> liveSessionStartedProps({
    required String gameType,
    required String currency,
  }) =>
      {'game_type': gameType, 'currency': currency};

  /// Fired when a live recording session is *started* (not finalized). Pair
  /// with the `session_logged{source:'live'}` finalize event to build a
  /// live-session completion funnel (started → finalized vs abandoned).
  static void liveSessionStarted({
    required String gameType,
    required String currency,
  }) {
    if (!_analyticsSupported) return;
    Posthog().capture(
      eventName: 'live_session_started',
      properties: liveSessionStartedProps(
        gameType: gameType,
        currency: currency,
      ),
    );
  }

  static void sessionDeleted() {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'session_deleted');
  }

  // ── AI features ─────────────────────────────────────────────────────────────

  static void aiSessionAnalysisRequested() {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'ai_session_analysis_requested');
  }

  static void aiHandAnalysisRequested() {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'ai_hand_analysis_requested');
  }

  static void aiRateLimitHit({required String featureType}) {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'ai_rate_limit_hit', properties: {
      'feature_type': featureType, // 'session' or 'hand'
    });
  }

  @visibleForTesting
  static Map<String, Object> aiAnalysisCompletedProps(
          {required String featureType}) =>
      {'feature_type': featureType};

  /// Fired when an analysis call returns successfully (the `_requested` events
  /// fire on attempt; this one closes the funnel so we can see request→result
  /// drop-off and at-capacity failures separately from rate limits).
  static void aiAnalysisCompleted({required String featureType}) {
    if (!_analyticsSupported) return;
    Posthog().capture(
      eventName: 'ai_analysis_completed',
      properties: aiAnalysisCompletedProps(featureType: featureType),
    );
  }

  @visibleForTesting
  static Map<String, Object> aiAnalysisRatedProps({
    required String featureType,
    required int rating,
  }) =>
      {'feature_type': featureType, 'rating': rating};

  /// Thumbs up/down on an analysis. Mirrors the DB rating write so the quality
  /// signal reaches PostHog and can be cohorted against retention.
  static void aiAnalysisRated({
    required String featureType,
    required int rating, // 1 (up) or -1 (down)
  }) {
    if (!_analyticsSupported) return;
    Posthog().capture(
      eventName: 'ai_analysis_rated',
      properties: aiAnalysisRatedProps(featureType: featureType, rating: rating),
    );
  }

  // ── Hands ───────────────────────────────────────────────────────────────────

  @visibleForTesting
  static Map<String, Object> handRecordedProps({
    required bool isTournament,
    String entryMode = 'full',
  }) =>
      {
        'is_tournament': isTournament,
        'entry_mode': entryMode, // 'full' or 'quick'
      };

  static void handRecorded(
      {required bool isTournament, String entryMode = 'full'}) {
    if (!_analyticsSupported) return;
    Posthog().capture(
      eventName: 'hand_recorded',
      properties:
          handRecordedProps(isTournament: isTournament, entryMode: entryMode),
    );
  }

  // ── Tools ───────────────────────────────────────────────────────────────────

  static void equityCalculatorUsed() {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'equity_calculator_used');
  }

  // ── Feedback ────────────────────────────────────────────────────────────────

  static void feedbackSubmitted({required String category}) {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'feedback_submitted', properties: {
      'category': category, // 'bug' | 'idea' | 'praise' | 'other'
    });
  }

  // ── Import / Export ─────────────────────────────────────────────────────────

  static void exportTriggered({required String format}) {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'export_triggered', properties: {
      'format': format, // 'csv' or 'excel'
    });
  }
}
