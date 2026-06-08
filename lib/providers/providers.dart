import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/session_model.dart';
import '../models/session_filter.dart';
import '../models/hand_model.dart';
import '../models/tournament_listing.dart';
import '../services/supabase_service.dart';
import '../services/hand_service.dart';
import '../services/ai_service.dart';

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

final filteredSessionsProvider = Provider<AsyncValue<List<SessionModel>>>((ref) {
  final filter = ref.watch(filterProvider);
  final sessionsAsync = ref.watch(sessionsProvider);
  if (filter.isEmpty) return sessionsAsync;
  return sessionsAsync.whenData(
    (sessions) => sessions.where(filter.matches).toList(),
  );
});

final distinctStakesProvider = Provider<AsyncValue<List<String>>>((ref) {
  return ref.watch(sessionsProvider).whenData(
    (sessions) => sessions
        .map((s) => s.stakes)
        .where((s) => s != 'N/A')
        .toSet()
        .toList()
      ..sort(),
  );
});

final distinctLocationsProvider = Provider<AsyncValue<List<String>>>((ref) {
  return ref.watch(sessionsProvider).whenData(
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

