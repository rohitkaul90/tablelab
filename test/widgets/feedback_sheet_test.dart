import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tablelab/providers/providers.dart';
import 'package:tablelab/services/feedback_service.dart';
import 'package:tablelab/widgets/feedback_sheet.dart';

/// Fake that records submit() calls instead of hitting the Edge Function.
class _FakeFeedbackService extends FeedbackService {
  bool wasCalled = false;
  String? category;
  String? message;
  int? rating;
  bool? shareEmail;
  Object? throwThis;

  @override
  Future<void> submit({
    required String category,
    required String message,
    int? rating,
    bool shareEmail = false,
  }) async {
    wasCalled = true;
    this.category = category;
    this.message = message;
    this.rating = rating;
    this.shareEmail = shareEmail;
    if (throwThis != null) throw throwThis!;
  }
}

Future<void> _open(WidgetTester tester, _FakeFeedbackService fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [feedbackServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showFeedbackSheet(ctx, initialCategory: 'idea'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // Swallow PostHog method-channel calls (the SDK isn't initialized in tests) so
  // the fire-and-forget AnalyticsService.feedbackSubmitted can't fail the test.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('posthog_flutter'), (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('posthog_flutter'), null);
  });

  testWidgets('empty message blocks submit and shows a prompt', (tester) async {
    final fake = _FakeFeedbackService();
    await _open(tester, fake);

    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(fake.wasCalled, isFalse);
    expect(find.text('Please write a little something first.'), findsOneWidget);
  });

  testWidgets('submits category + message and closes the sheet', (tester) async {
    final fake = _FakeFeedbackService();
    await _open(tester, fake);

    await tester.enterText(find.byType(TextField), 'Add a hand-history importer');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(fake.wasCalled, isTrue);
    expect(fake.category, 'idea'); // preselected via initialCategory
    expect(fake.message, 'Add a hand-history importer');
    expect(fake.shareEmail, isFalse);
    // Sheet dismissed, thank-you shown.
    expect(find.text('Send'), findsNothing);
    expect(find.text('Thanks for the feedback! 🙏'), findsOneWidget);
  });

  testWidgets('surfaces a network error and keeps the sheet open on failure',
      (tester) async {
    final fake = _FakeFeedbackService()..throwThis = Exception('network');
    await _open(tester, fake);

    await tester.enterText(find.byType(TextField), 'Something broke');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(fake.wasCalled, isTrue);
    expect(find.text('Send'), findsOneWidget); // still open
    expect(
      find.textContaining("Couldn't send feedback. Check your connection"),
      findsOneWidget,
    );
  });

  testWidgets('shows the limit message on a 429 FeedbackException',
      (tester) async {
    final fake = _FakeFeedbackService()
      ..throwThis = const FeedbackException(status: 429, message: 'Daily feedback limit reached.');
    await _open(tester, fake);

    await tester.enterText(find.byType(TextField), 'One too many');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Send'), findsOneWidget); // still open
    expect(find.textContaining('Daily feedback limit reached'), findsOneWidget);
  });
}
