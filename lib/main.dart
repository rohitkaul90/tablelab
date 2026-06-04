import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';
import 'config/analytics_config.dart';
import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'screens/hands_screen.dart';
import 'screens/reads_screen.dart';
import 'screens/session_history_screen.dart';
import 'screens/tools_screen.dart';
import 'widgets/app_drawer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase/Crashlytics is Android/iOS only — skip entirely on web.
  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Don't report crashes from debug builds (e.g. `flutter run` on a device) —
    // they pollute the production Crashlytics view with debug-only asserts that
    // can't happen in release. Collection stays on for release/profile builds.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
      final phConfig = PostHogConfig(posthogApiKey)..host = posthogHost;
      await Posthog().setup(phConfig);
    } catch (_) {
      // Non-fatal — analytics failure must never crash the app.
    }
  }

  runApp(const ProviderScope(child: PokerTrackerApp()));
}

class PokerTrackerApp extends StatelessWidget {
  const PokerTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TableLab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: mainScaffoldKey,
      drawer: const AppDrawer(),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          DashboardScreen(),
          SessionHistoryScreen(),
          HandsScreen(),
          ReadsScreen(),
          ToolsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_outlined),
            selectedIcon: Icon(Icons.list),
            label: 'Sessions',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: 'Hands',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Reads',
          ),
          NavigationDestination(
            icon: Icon(Icons.construction_outlined),
            selectedIcon: Icon(Icons.construction),
            label: 'Tools',
          ),
        ],
      ),
    );
  }
}
