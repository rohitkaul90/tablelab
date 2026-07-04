import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';
import 'config/analytics_config.dart';
import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'providers/theme_provider.dart';
import 'services/analytics_service.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/hands_screen.dart';
import 'screens/reads_screen.dart';
import 'screens/session_history_screen.dart';
import 'screens/explorer/gto_explorer_screen.dart';
import 'providers/explorer_provider.dart';
import 'widgets/app_drawer.dart';

/// Expected, recoverable auth failures that should not be reported as fatal
/// crashes. The canonical case is a revoked/expired refresh token surfacing
/// asynchronously during `recoverSession()` on cold start (Crashlytics issue
/// "Invalid Refresh Token: Refresh Token Not Found"): the SDK signs the user
/// out and `AuthGate` shows the login screen — the user simply re-authenticates.
bool _isRecoverableAuthError(Object error) {
  if (error is! AuthException) return false;
  final code = error.code?.toLowerCase() ?? '';
  final message = error.message.toLowerCase();
  return error is AuthSessionMissingException ||
      code.contains('refresh_token') ||
      message.contains('refresh token');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase/Crashlytics is Android/iOS only — skip on web AND desktop.
  // firebase_crashlytics has no Windows/Linux/macOS implementation: on those,
  // the awaited setCrashlyticsCollectionEnabled throws a platform-interface
  // assertion INSIDE main(), which aborts startup before runApp — the app
  // process runs but no window ever appears (hit on `flutter run -d windows`).
  final crashlyticsSupported = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (crashlyticsSupported) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Don't report crashes from debug builds (e.g. `flutter run` on a device) —
    // they pollute the production Crashlytics view with debug-only asserts that
    // can't happen in release. Collection stays on for release/profile builds.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = (details) {
      if (_isRecoverableAuthError(details.exception)) {
        FirebaseCrashlytics.instance.recordFlutterError(details); // non-fatal
        return;
      }
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      // A revoked/expired stored refresh token makes the SDK throw
      // asynchronously from inside recoverSession() at startup — there's no
      // app-level call site to try/catch. It's not a crash: the SDK emits a
      // signedOut event and AuthGate falls back to the login screen. Record it
      // non-fatal for visibility instead of letting it count as a fatal crash.
      FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: !_isRecoverableAuthError(error));
      return true;
    };
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // PostHog analytics — no-op until posthogApiKey is replaced in analytics_config.dart.
  // Not supported on Windows desktop (skipped automatically by AnalyticsService).
  if (posthogApiKey != 'phc_REPLACE_WITH_YOUR_KEY' &&
      defaultTargetPlatform != TargetPlatform.windows) {
    try {
      final phConfig = PostHogConfig(posthogApiKey)
        ..host = posthogHost
        // App-open/lifecycle events give us DAU + retention without depending
        // on the user performing a tracked action each visit.
        ..captureApplicationLifecycleEvents = true;
      await Posthog().setup(phConfig);
    } catch (_) {
      // Non-fatal — analytics failure must never crash the app.
    }
  }

  // Tie PostHog persons to Supabase accounts so the People page shows real
  // users (by email) instead of anonymous device IDs. Reset on sign-out so a
  // shared device doesn't attribute the next user's events to the previous one.
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    final event = state.event;
    final user = state.session?.user;
    if ((event == AuthChangeEvent.initialSession ||
            event == AuthChangeEvent.signedIn) &&
        user != null) {
      AnalyticsService.identify(
        user.id,
        email: user.email,
        // GoTrue records the primary provider here ('email' | 'google');
        // mirrors auth.identities.provider, set once as a person property.
        signupMethod: user.appMetadata['provider'] as String?,
      );
    } else if (event == AuthChangeEvent.signedOut) {
      AnalyticsService.reset();
    }
  });

  // Load persisted preferences (theme mode) before the first frame so the
  // chosen theme applies immediately — no dark→light flash on cold start.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const PokerTrackerApp(),
    ),
  );
}

class PokerTrackerApp extends ConsumerWidget {
  const PokerTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'TableLab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const AuthGate(),
      // Incoming platform route pushes (the io.supabase.pokertracker OAuth /
      // email-confirmation deep link, or an OS-supplied launch route) are
      // delivered to the Navigator as *named* routes. This app navigates
      // imperatively (Navigator.push only) with no named routes, so without a
      // fallback the framework hits `widget.onUnknownRoute!` on a null value and
      // crashes in release (the guarding assert is stripped). Supabase handles
      // the deep link via its own listener, so we just route any unknown push
      // back to AuthGate to swallow it safely.
      onUnknownRoute: (settings) =>
          MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }
}

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Resolve the Study tab's visibility up front (a cheap local pack-dir scan;
    // a no-op on web until hosted packs land) so the tab can appear without the
    // Study screen ever mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(explorerProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Study is a real bottom tab, but only when there is something to study (or
    // in debug builds). Prod users must never see a permanently dead tab —
    // today's only pack source is a local dev directory; hosted packs light it
    // up later. The calculators (Equity/ICM) now live in the drawer's Tools.
    final showStudy =
        kDebugMode || ref.watch(explorerProvider).spots.isNotEmpty;
    // Study focus mode hides the bottom nav for a full-window spot view.
    final maximized = ref.watch(studyMaximizedProvider);

    final tabs = <Widget>[
      const DashboardScreen(),
      const SessionHistoryScreen(),
      const HandsScreen(),
      const ReadsScreen(),
      if (showStudy) const GtoExplorerScreen(),
    ];
    // Keep the selection in range if Study disappears while it was selected.
    final index = _currentIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      key: mainScaffoldKey,
      drawer: const AppDrawer(),
      body: IndexedStack(
        index: index,
        children: tabs,
      ),
      // Cap text scaling for the bottom bar so its labels stay single-line. On a
      // large system font setting (e.g. Samsung "Large" font / screen zoom) the
      // longest label wrapped to two lines within its equal-width slot. Clamping
      // to 1.0 keeps all labels on one line. Hidden in Study focus mode.
      bottomNavigationBar: maximized
          ? null
          : MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.0,
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Stats',
            ),
            const NavigationDestination(
              icon: Icon(Icons.list_outlined),
              selectedIcon: Icon(Icons.list),
              label: 'Sessions',
            ),
            const NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style),
              label: 'Hands',
            ),
            const NavigationDestination(
              icon: Icon(Icons.psychology_outlined),
              selectedIcon: Icon(Icons.psychology),
              label: 'Reads',
            ),
            if (showStudy)
              const NavigationDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: 'Study',
              ),
          ],
        ),
      ),
    );
  }
}
