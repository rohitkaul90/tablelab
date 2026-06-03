import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../providers/profile_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/onboarding_screen.dart';
import '../widgets/splash_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final Widget child;

        if (!snapshot.hasData) {
          child = const SplashScreen(key: ValueKey('splash'));
        } else {
          final event = snapshot.data!.event;
          final session = snapshot.data!.session;

          // Token is expired on startup — keep splash while SDK auto-refreshes.
          if (event == AuthChangeEvent.initialSession &&
              session != null &&
              _isExpired(session)) {
            child = const SplashScreen(key: ValueKey('splash'));
          } else if (session == null) {
            child = const LoginScreen(key: ValueKey('login'));
          } else if (event == AuthChangeEvent.passwordRecovery) {
            child = const ResetPasswordScreen(key: ValueKey('reset'));
          } else {
            child = const _OnboardingGate(key: ValueKey('authed'));
          }
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: child,
        );
      },
    );
  }

  bool _isExpired(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch >= expiresAt * 1000;
  }
}

// Checks onboarding state after auth resolves.
// New users (no profile row) and users with hasSeenOnboarding=false see OnboardingScreen.
class _OnboardingGate extends ConsumerStatefulWidget {
  const _OnboardingGate({super.key});

  @override
  ConsumerState<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<_OnboardingGate> {
  // fetchProfile already retries transient failures; these are a few extra
  // bounded retries at the gate before falling back to the dashboard, so a
  // one-off error doesn't wrongly send a brand-new user past onboarding.
  static const _maxRetries = 2;
  int _retries = 0;
  bool _retryPending = false;

  void _scheduleRetry() {
    if (_retryPending || _retries >= _maxRetries) return;
    _retryPending = true;
    _retries++;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _retryPending = false;
      ref.invalidate(profileProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      loading: () => const SplashScreen(key: ValueKey('splash-profile')),
      error: (_, _) {
        if (_retries < _maxRetries) {
          _scheduleRetry();
          return const SplashScreen(key: ValueKey('splash-profile'));
        }
        // Retries exhausted — fall back to the dashboard rather than blocking.
        return const MainNavigation(key: ValueKey('main'));
      },
      data: (profile) {
        _retries = 0; // reset after a successful fetch
        if (profile == null || !profile.hasSeenOnboarding) {
          return const OnboardingScreen(key: ValueKey('onboarding'));
        }
        return const MainNavigation(key: ValueKey('main'));
      },
    );
  }
}
