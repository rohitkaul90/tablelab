import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/services/analytics_service.dart';

// These assert the event PROPERTY MAPS rather than mocking the PostHog method
// channel: the posthog_flutter IO implementation early-returns on
// Platform.isWindows (real dart:io, not overridable) before invoking the
// channel, so on a Windows host the capture call is unobservable. The pure
// `*Props` builders are the testable seam (cf. AiUsage.fromRows).
void main() {
  group('sessionLoggedProps', () {
    test('carries source for a past (manual) session', () {
      final p = AnalyticsService.sessionLoggedProps(
        gameType: 'cash',
        currency: 'USD',
        hasNotes: true,
        source: 'past',
      );
      expect(p, {
        'game_type': 'cash',
        'currency': 'USD',
        'has_notes': true,
        'source': 'past',
      });
    });

    test('carries source for a finalized live session', () {
      final p = AnalyticsService.sessionLoggedProps(
        gameType: 'tournament',
        currency: 'EUR',
        hasNotes: false,
        source: 'live',
      );
      expect(p['source'], 'live');
      expect(p['game_type'], 'tournament');
      expect(p['has_notes'], false);
    });
  });

  group('liveSessionStartedProps', () {
    test('carries game type and currency', () {
      expect(
        AnalyticsService.liveSessionStartedProps(
          gameType: 'cash',
          currency: 'GBP',
        ),
        {'game_type': 'cash', 'currency': 'GBP'},
      );
    });
  });

  group('handRecordedProps (quick vs full)', () {
    test('quick entry mode is tagged', () {
      final p = AnalyticsService.handRecordedProps(
        isTournament: false,
        entryMode: 'quick',
      );
      expect(p['entry_mode'], 'quick');
      expect(p['is_tournament'], false);
    });

    test('defaults to full entry mode', () {
      final p = AnalyticsService.handRecordedProps(isTournament: true);
      expect(p['entry_mode'], 'full');
      expect(p['is_tournament'], true);
    });
  });

  group('aiAnalysisCompletedProps', () {
    test('carries feature type', () {
      expect(
        AnalyticsService.aiAnalysisCompletedProps(featureType: 'hand'),
        {'feature_type': 'hand'},
      );
      expect(
        AnalyticsService.aiAnalysisCompletedProps(featureType: 'session'),
        {'feature_type': 'session'},
      );
    });
  });

  group('aiAnalysisRatedProps', () {
    test('thumbs up carries rating 1', () {
      expect(
        AnalyticsService.aiAnalysisRatedProps(featureType: 'hand', rating: 1),
        {'feature_type': 'hand', 'rating': 1},
      );
    });

    test('thumbs down carries rating -1', () {
      final p = AnalyticsService.aiAnalysisRatedProps(
        featureType: 'session',
        rating: -1,
      );
      expect(p['rating'], -1);
      expect(p['feature_type'], 'session');
    });
  });
}
