import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/providers/providers.dart';
import 'package:tablelab/services/feedback_service.dart';
import 'package:tablelab/widgets/feedback_sheet.dart';

import '../helpers/pump_app.dart';

/// Fake that records submit() calls instead of hitting the Edge Function.
class _FakeFeedbackService extends FeedbackService {
  bool wasCalled = false;
  String? category;
  String? message;
  int? rating;
  bool? shareEmail;
  Object? throwThis;

  /// When set, submit() stays pending until this completes (a stalled call).
  Completer<void>? hang;

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
    if (hang != null) await hang!.future;
    if (throwThis != null) throw throwThis!;
  }
}

/// Holds the sheet's result future so tests can assert the documented
/// true / false / null contract of [showFeedbackSheet].
class _Opened {
  Future<bool?>? result;
}

Future<_Opened> _open(WidgetTester tester, _FakeFeedbackService fake) async {
  final opened = _Opened();
  await tester.pumpWidget(
    wrapApp(
      Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () =>
                opened.result = showFeedbackSheet(ctx, initialCategory: 'idea'),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [feedbackServiceProvider.overrideWithValue(fake)],
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  // Swallow PostHog method-channel calls (the SDK isn't initialized in tests) so
  // the fire-and-forget AnalyticsService.feedbackSubmitted can't fail the test.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('posthog_flutter'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('posthog_flutter'), null);
  });

  testWidgets('empty message blocks submit and shows a prompt', (tester) async {
    final fake = _FakeFeedbackService();
    await _open(tester, fake);

    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(fake.wasCalled, isFalse);
    expect(find.text('Please write a little something first.'), findsOneWidget);
  });

  testWidgets('close button dismisses the sheet without submitting', (
    tester,
  ) async {
    // iOS has no system back gesture for a modal sheet, and with the
    // autofocused keyboard up there is no scrim to tap, so the header X is
    // the only discoverable exit there.
    final fake = _FakeFeedbackService();
    final opened = await _open(tester, fake);

    await tester.enterText(find.byType(TextField), 'Changed my mind');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(fake.wasCalled, isFalse);
    expect(find.text('Send'), findsNothing);
    // X = explicit cancel (false), distinct from a barrier dismiss (null).
    expect(await opened.result, isFalse);
  });

  testWidgets('close stays usable while a submit is stalled', (tester) async {
    // A hung Edge Function call must not re-create the trap: every other
    // control is disabled during _saving, the X must not be.
    final fake = _FakeFeedbackService()..hang = Completer<void>();
    final opened = await _open(tester, fake);

    await tester.enterText(find.byType(TextField), 'Slow network');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(fake.wasCalled, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // saving

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);
    expect(await opened.result, isFalse);

    // Let the orphaned call finish; the mounted guard must swallow it.
    fake.hang!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('submits category + message and closes the sheet', (
    tester,
  ) async {
    final fake = _FakeFeedbackService();
    await _open(tester, fake);

    await tester.enterText(
      find.byType(TextField),
      'Add a hand-history importer',
    );
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

  testWidgets('surfaces a network error and keeps the sheet open on failure', (
    tester,
  ) async {
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

  testWidgets('shows the limit message on a 429 FeedbackException', (
    tester,
  ) async {
    final fake = _FakeFeedbackService()
      ..throwThis = const FeedbackException(
        status: 429,
        message: 'Daily feedback limit reached.',
      );
    await _open(tester, fake);

    await tester.enterText(find.byType(TextField), 'One too many');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Send'), findsOneWidget); // still open
    expect(find.textContaining('Daily feedback limit reached'), findsOneWidget);
  });
}
