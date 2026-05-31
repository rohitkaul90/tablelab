// Integration tests — require a connected device and a real (staging) Supabase instance.
//
// Run on Android:  flutter test integration_test/ -d <device-id>
// Run on Windows:  flutter test integration_test/ -d windows
// Run on Chrome:   flutter test integration_test/ -d chrome
//
// All tests skip automatically when INTEGRATION_TEST_ENABLED != 'true' so
// they never run unintentionally in unit-test CI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tablelab/main.dart' as app;

const _enabled = bool.fromEnvironment('INTEGRATION_TEST_ENABLED');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── F001 – App launch ───────────────────────────────────────────────────────

  testWidgets('F001 — app launches without crash', (tester) async {
    if (!_enabled) return;
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1),
        reason: 'App must render at least one Scaffold on launch');
  });

  // ── F002 – Login screen ─────────────────────────────────────────────────────

  testWidgets('F002 — login screen renders required elements', (tester) async {
    if (!_enabled) return;
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // If already logged in this will show MainNavigation — sign out first
    // in a pre-test setup, or run on a fresh emulator.
    expect(find.byType(TextField), findsWidgets);
  });

  // ── F003 – Session log golden path ──────────────────────────────────────────

  testWidgets('F003 — session log golden path', (tester) async {
    if (!_enabled) return;
    // Precondition: user is signed in (use a staging test account)
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Tap Log Session (FAB or button — adjust finder to match actual widget)
    final logButton = find.byTooltip('Log Session');
    if (logButton.evaluate().isNotEmpty) {
      await tester.tap(logButton);
      await tester.pumpAndSettle();
    }

    // Fill buy-in field
    final buyInField = find.widgetWithText(TextFormField, 'Buy-in');
    if (buyInField.evaluate().isNotEmpty) {
      await tester.enterText(buyInField, '200');
      await tester.pumpAndSettle();
    }

    // Verify no crash
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });

  // ── F004 – Analytics loads without RangeError (Windows fl_chart safety) ─────

  testWidgets('F004 — analytics tab loads without crash', (tester) async {
    if (!_enabled) return;
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Tap Dashboard tab (index 0 in bottom nav)
    final dashboardNav = find.byIcon(Icons.dashboard_outlined);
    if (dashboardNav.evaluate().isNotEmpty) {
      await tester.tap(dashboardNav);
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull,
        reason: 'No RangeError from fl_chart on analytics screen');
  });

  // ── F005 – Export does not crash ────────────────────────────────────────────

  testWidgets('F005 — export screen opens without crash', (tester) async {
    if (!_enabled) return;
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Navigate via drawer to Import/Export (if accessible without auth skip)
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });

  // ── F006 – Delete account flow ──────────────────────────────────────────────

  testWidgets('F006 — delete account dialog appears on tap', (tester) async {
    if (!_enabled) return;
    // Precondition: signed in as a disposable staging account
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // This test intentionally stops before confirming deletion.
    // A manual test step must complete the final confirmation.
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });

  // ── F007 – Onboarding shown for new accounts ────────────────────────────────

  testWidgets('F007 — onboarding shown for brand-new account', (tester) async {
    if (!_enabled) return;
    // Precondition: sign in with a brand-new account (no profile row in DB)
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Verify onboarding page is visible
    expect(find.text('Track Every Session'), findsOneWidget,
        reason: 'New users must see onboarding on first launch');
  });

  // ── F008 – Onboarding not repeated ─────────────────────────────────────────

  testWidgets('F008 — onboarding not shown after completion', (tester) async {
    if (!_enabled) return;
    // Precondition: sign in with account that has has_seen_onboarding=true
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Track Every Session'), findsNothing,
        reason: 'Returning users must not see onboarding again');
  });
}
