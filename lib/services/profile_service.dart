import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';
import 'supabase_retry.dart';

class ProfileService {
  /// [client] is injectable for tests; production uses the global Supabase
  /// client, resolved lazily so the service can be constructed (and faked)
  /// without an initialized Supabase instance.
  ProfileService([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  String? get uid => _client.auth.currentUser?.id;
  String? get email => _client.auth.currentUser?.email;
  String? get googleName =>
      _client.auth.currentUser?.userMetadata?['full_name'] as String?;
  String? get googleAvatarUrl =>
      _client.auth.currentUser?.userMetadata?['avatar_url'] as String?;

  Future<ProfileModel?> fetchProfile() async {
    final id = uid;
    if (id == null) return null;

    // The auth session is often briefly unstable right after an OAuth redirect
    // (especially on mobile web), causing the first profile fetch to throw.
    // Retry transient failures with short backoff so the onboarding gate isn't
    // handed an error for what is really a momentary blip. A missing row returns
    // null (a valid result for a brand-new user) and is not retried.
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await withSupabaseRetry(() async {
          final data = await _client
              .from('profiles')
              .select()
              .eq('id', id)
              .maybeSingle();
          if (data == null) return null;
          return ProfileModel.fromJson(data);
        });
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        }
      }
    }
    throw lastError!;
  }

  Future<ProfileModel> upsertProfile(ProfileModel profile) =>
      withSupabaseRetry(() async {
        final data = await _client
            .from('profiles')
            .upsert(profile.toUpsert())
            .select()
            .single();
        return ProfileModel.fromJson(data);
      });

  Future<void> markOnboardingComplete() async {
    final id = uid;
    if (id == null) return;
    await withSupabaseRetry(() => _client.from('profiles').upsert(
          {'id': id, 'has_seen_onboarding': true},
          onConflict: 'id',
        ));
  }
}
