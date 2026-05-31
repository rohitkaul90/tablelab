import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

// PostHog Flutter SDK supports Android, iOS, Web, macOS, Linux.
// Windows desktop is not supported — all calls are no-ops there.
bool get _analyticsSupported =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.windows;

class AnalyticsService {
  static Future<void> identify(String userId) async {
    if (!_analyticsSupported) return;
    await Posthog().identify(userId: userId);
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

  static void sessionLogged({
    required String gameType,
    required String currency,
    required bool hasNotes,
  }) {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'session_logged', properties: {
      'game_type': gameType,
      'currency': currency,
      'has_notes': hasNotes,
    });
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

  // ── Hands ───────────────────────────────────────────────────────────────────

  static void handRecorded({required bool isTournament}) {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'hand_recorded', properties: {
      'is_tournament': isTournament,
    });
  }

  // ── Tools ───────────────────────────────────────────────────────────────────

  static void equityCalculatorUsed() {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'equity_calculator_used');
  }

  // ── Import / Export ─────────────────────────────────────────────────────────

  static void exportTriggered({required String format}) {
    if (!_analyticsSupported) return;
    Posthog().capture(eventName: 'export_triggered', properties: {
      'format': format, // 'csv' or 'excel'
    });
  }
}
