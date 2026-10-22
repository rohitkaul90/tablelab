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
import 'recovery_link.dart';
import '../l10n/l10n.dart';
import '../providers/recovery_link_provider.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  /// The last stream error already announced to a signed-in user (SnackBar),
  /// so a rebuild doesn't repeat it.
  Object? _announcedError;

  @override
  void initState() {
    super.initState();
    // ONE app-level handler (a second AuthGate from onUnknownRoute shares it);
    // start() is idempotent. Redeems token-hash recovery links; a success
    // surfaces as AuthChangeEvent.passwordRecovery on the stream below.
    ref.read(recoveryLinkHandlerProvider).start();
  }

  /// Clears the link notice once it has served its purpose (a session exists
  /// again), so a later sign-out doesn't resurrect it on the login screen.
  void _clearLinkErrorLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(authLinkErrorProvider.notifier).state = null;
    });
  }

  /// A signed-in user who opened a failing link gets told so (the main app
  /// renders, nothing visibly happens otherwise).
  void _announceToSignedInUser(Object error) {
    if (identical(_announcedError, error)) return;
    _announcedError = error;
    final l10n = context.l10n;
    final text = authLinkErrorMessage(l10n, classifyAuthLinkError(error));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final linkError = ref.watch(authLinkErrorProvider);
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final Widget child;

        if (snapshot.hasError) {
          // The SDK reports a failed link redemption (e.g. a PKCE code opened
          // on a device that never requested it) as a stream ERROR, and a
          // StreamBuilder drops its data on error — this used to fall through
          // to the splash forever. Session-refresh failures arrive the same
          // way and are NOT link problems (isLinkError), so they get the plain
          // login screen. A signed-in user keeps their session.
          final error = snapshot.error!;
          final session = Supabase.instance.client.auth.currentSession;
          final link = isLinkError(error);
          if (session != null) {
            if (link) _announceToSignedInUser(error);
            child = const _OnboardingGate(key: ValueKey('authed'));
          } else {
            child = LoginScreen(
              key: const ValueKey('login'),
              notice: link ? classifyAuthLinkError(error) : null,
            );
          }
        } else if (!snapshot.hasData) {
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
            child = LoginScreen(
              key: const ValueKey('login'),
              notice: linkError,
            );
          } else if (event == AuthChangeEvent.passwordRecovery) {
            if (linkError != null) _clearLinkErrorLater();
            child = const ResetPasswordScreen(key: ValueKey('reset'));
          } else {
            if (linkError != null) {
              // A signed-in user's token-hash link failed (e.g. expired):
              // say so once, then forget it.
              _announceToSignedInUser(linkError);
              _clearLinkErrorLater();
            }
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
