import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/screens/auth/login_screen.dart';

// Wrap LoginScreen in a minimal MaterialApp so Theme / Navigator work.
Widget _buildLoginScreen() => const MaterialApp(home: LoginScreen());

void main() {
  // Flutter test runner can't load real font glyphs; suppress asset warnings.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoginScreen — rendering', () {
    testWidgets('shows email field, password field, Sign In button', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump(); // let async frame settle

      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
    });

    testWidgets('shows "Sign in to continue" subtitle in sign-in mode', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      expect(find.text('Sign in to continue'), findsOneWidget);
    });

    testWidgets('shows Forgot password link in sign-in mode', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('shows Privacy Policy button', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('shows Continue with Google button', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      expect(find.text('Continue with Google'), findsOneWidget);
    });
  });

  group('LoginScreen — register mode toggle', () {
    testWidgets('tapping toggle switches to register mode', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.tap(find.text("Don't have an account? Create one"));
      await tester.pump();

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create Account'), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
    });

    testWidgets('Forgot password link hidden in register mode', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.tap(find.text("Don't have an account? Create one"));
      await tester.pump();

      expect(find.text('Forgot password?'), findsNothing);
    });

    testWidgets('toggling back to sign-in mode restores sign-in UI', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      // → register
      await tester.tap(find.text("Don't have an account? Create one"));
      await tester.pump();
      // → back to sign-in
      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pump();

      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
    });
  });

  group('LoginScreen — form validation', () {
    testWidgets('empty email shows Required error', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();

      expect(find.text('Required'), findsAtLeastNWidgets(1));
    });

    testWidgets('invalid email (no @) shows validation error', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'notanemail');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('empty password shows Required error', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@test.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('short password in register mode shows length error', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      // Switch to register mode
      await tester.tap(find.text("Don't have an account? Create one"));
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@test.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'abc');

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.text('At least 6 characters'), findsOneWidget);
    });

    testWidgets('6-char password in register mode passes length check', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.tap(find.text("Don't have an account? Create one"));
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@test.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'abcdef');

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      // No length error — validation passes; only Supabase call would follow
      expect(find.text('At least 6 characters'), findsNothing);
    });
  });
}
