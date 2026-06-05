import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tablelab/models/profile_model.dart';
import 'package:tablelab/providers/profile_provider.dart';
import 'package:tablelab/screens/profile_screen.dart';
import 'package:tablelab/services/profile_service.dart';

/// Fake that avoids Supabase entirely (enabled by the ProfileService DI
/// refactor — the super constructor no longer touches Supabase.instance).
class _FakeProfileService extends ProfileService {
  _FakeProfileService(this._profile);

  final ProfileModel _profile;
  ProfileModel? captured;

  @override
  String? get uid => _profile.id;
  @override
  String? get email => 'tester@example.com';
  @override
  String? get googleName => null;
  @override
  String? get googleAvatarUrl => null;

  @override
  Future<ProfileModel?> fetchProfile() async => _profile;

  @override
  Future<ProfileModel> upsertProfile(ProfileModel profile) async {
    captured = profile;
    return profile;
  }
}

void main() {
  testWidgets(
      'Saving the profile preserves hasSeenOnboarding (no onboarding bounce)',
      (tester) async {
    final fake = _FakeProfileService(
      const ProfileModel(
        id: 'test-uid',
        displayName: 'Rohit',
        hasSeenOnboarding: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The loaded profile populated the form.
    expect(find.text('Rohit'), findsOneWidget);

    // Tap the AppBar "Save" action and let the async save run.
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump(); // start _save
    await tester.pump(); // resolve upsert + continue

    expect(fake.captured, isNotNull, reason: 'Save should call upsertProfile');
    expect(
      fake.captured!.hasSeenOnboarding,
      isTrue,
      reason: 'Saving the profile must NOT reset has_seen_onboarding — '
          'doing so previously bounced users into onboarding.',
    );

    // Flush the post-save SnackBar timer and route pop so no timers leak.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
