import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/session_model.dart';
import '../models/session_filter.dart';
import '../models/hand_model.dart';
import '../models/hand_filter.dart';
import '../models/tournament_listing.dart';
import '../services/supabase_service.dart';
import '../services/hand_service.dart';
import '../services/ai_service.dart';
import '../services/feedback_service.dart';

export '../models/session_filter.dart' show SessionFilter, SessionResult;

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

// Emits the current user's ID whenever auth state changes.
// Providers that watch this will automatically restart on account switch.
final authUserIdProvider = StreamProvider<String?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session?.user.id);
});

final sessionsProvider = FutureProvider<List<SessionModel>>((ref) {
  ref.watch(authUserIdProvider); // re-fetch when user changes
  return ref.watch(supabaseServiceProvider).fetchAllSessions();
});

final filterProvider = StateProvider<SessionFilter>((ref) => const SessionFilter());

/// The single in-progress (live) session, or null. There is at most one at a
/// time (enforced by the start flow). Reads the raw [sessionsProvider] so it
/// still sees the live row even though stats/list providers exclude it.
final liveSessionProvider = Provider<AsyncValue<SessionModel?>>((ref) {
  return ref.watch(sessionsProvider).whenData(
        (sessions) => sessions.where((s) => s.isLive).firstOrNull,
      );
});

/// Completed sessions only — the base for all stats, the bankroll graph, the
/// Sessions list, and the filter/dropdown options. A live session is excluded
/// until it's finalized (it would otherwise pollute P&L with a partial result).
final completedSessionsProvider = Provider<AsyncValue<List<SessionModel>>>((ref) {
  return ref.watch(sessionsProvider).whenData(
        (sessions) => sessions.where((s) => !s.isLive).toList(),
      );
});

final filteredSessionsProvider = Provider<AsyncValue<List<SessionModel>>>((ref) {
  final filter = ref.watch(filterProvider);
  final sessionsAsync = ref.watch(completedSessionsProvider);
  if (filter.isEmpty) return sessionsAsync;
  return sessionsAsync.whenData(
    (sessions) => sessions.where(filter.matches).toList(),
  );
});

final distinctStakesProvider = Provider<AsyncValue<List<String>>>((ref) {
  return ref.watch(completedSessionsProvider).whenData(
    (sessions) => sessions
        .map((s) => s.stakes)
        .where((s) => s != 'N/A')
        .toSet()
        .toList()
      ..sort(),
  );
});

final distinctLocationsProvider = Provider<AsyncValue<List<String>>>((ref) {
  return ref.watch(completedSessionsProvider).whenData(
    (sessions) => sessions
        .map((s) => s.location)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort(),
  );
});

final handServiceProvider = Provider<HandService>((ref) => HandService());

final handsProvider = FutureProvider<List<PokerHand>>((ref) {
  ref.watch(authUserIdProvider); // re-fetch when user changes
  return ref.read(handServiceProvider).fetchHands();
});

/// Active filter for the Hands tab (funnel). AND-ed criteria; see [HandFilter].
final handFilterProvider =
    StateProvider<HandFilter>((ref) => const HandFilter());

final aiServiceProvider = Provider<AiService>((ref) => AiService());

/// Current 24h AI usage (session + hand analysis counts, exempt flag), feeding
/// the contextual quota indicators at the AI entry points. Watches
/// [authUserIdProvider] so it restarts on account switch. Invalidate after any
/// AI analysis call so the remaining count stays accurate (there is no
/// Realtime push).
final aiUsageProvider = FutureProvider<AiUsage>((ref) {
  ref.watch(authUserIdProvider);
  return ref.read(aiServiceProvider).fetchUsageLast24h();
});

final tournamentListingsProvider = FutureProvider.autoDispose<List<TournamentListing>>((ref) {
  return ref.read(supabaseServiceProvider).fetchTournamentListings();
});

final feedbackServiceProvider = Provider<FeedbackService>((ref) => FeedbackService());

