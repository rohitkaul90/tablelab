import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/hand_model.dart';
import 'package:tablelab/providers/providers.dart';
import 'package:tablelab/screens/hand_input/quick_hand_screen.dart';
import 'package:tablelab/services/hand_service.dart';

/// Avoids Supabase entirely — HandService resolves its client lazily, so a
/// subclass that overrides saveHand never touches Supabase.instance.
class FakeHandService extends HandService {
  int saveCalls = 0;
  TableSetup? capturedSetup;
  List<StreetData>? capturedStreets;
  String? capturedNotes;
  String? capturedSessionId;
  bool? capturedIsTournament;
  bool? capturedIsQuickEntry;
  Duration delay;

  FakeHandService({this.delay = Duration.zero});

  @override
  Future<PokerHand> saveHand({
    required TableSetup tableSetup,
    required List<HandPlayer> players,
    required List<StreetData> streets,
    String? sessionId,
    String? notes,
    String? tournamentStage,
    bool isTournament = false,
    bool isQuickEntry = false,
  }) async {
    saveCalls++;
    capturedSetup = tableSetup;
    capturedStreets = streets;
    capturedNotes = notes;
    capturedSessionId = sessionId;
    capturedIsTournament = isTournament;
    capturedIsQuickEntry = isQuickEntry;
    await Future<void>.delayed(delay);
    return PokerHand(
      id: 'h1',
      userId: 'u1',
      playedAt: DateTime(2026, 1, 1),
      tableSetup: tableSetup,
      players: players,
      streets: streets,
      notes: notes,
      isTournament: isTournament,
      isQuickEntry: isQuickEntry,
    );
  }
}

/// The form is a single tall ListView; a phone-sized test viewport leaves the
/// lower fields unbuilt (lazy list), so give the tests a tall surface.
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> pumpQuickHand(WidgetTester tester, FakeHandService fake,
    {String? prefilledSessionId,
    String? prefilledStakes,
    bool isTournamentSession = false}) async {
  useTallViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [handServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: QuickHandScreen(
          prefilledSessionId: prefilledSessionId,
          prefilledStakes: prefilledStakes,
          isTournamentSession: isTournamentSession,
        ),
      ),
    ),
  );
}

QuickHandScreenState stateOf(WidgetTester tester) =>
    tester.state<QuickHandScreenState>(find.byType(QuickHandScreen));

void main() {
  testWidgets('save is disabled until the required fields are set',
      (tester) async {
    final fake = FakeHandService();
    await pumpQuickHand(tester, fake);

    final save = find.widgetWithText(FilledButton, 'Save Hand');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    // Hero cards + position + action (stakes default to 1/2).
    stateOf(tester).debugSetHeroCards(['As', 'Kd']);
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'CO'));
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Fold'));
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('minimal fill saves once with isQuickEntry and pops',
      (tester) async {
    final fake = FakeHandService();
    useTallViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [handServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const QuickHandScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    stateOf(tester).debugSetHeroCards(['As', 'Kd']);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'BTN'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Raise'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Hand'));
    await tester.pumpAndSettle();

    expect(fake.saveCalls, equals(1));
    expect(fake.capturedIsQuickEntry, isTrue);
    expect(fake.capturedIsTournament, isFalse);
    expect(fake.capturedSetup!.smallBlind, equals(1));
    expect(fake.capturedSetup!.bigBlind, equals(2));
    expect(fake.capturedStreets!.length, equals(1));
    expect(fake.capturedNotes, startsWith('[Quick entry'));
    // Screen popped back to the host.
    expect(find.byType(QuickHandScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('double-tapping save calls the service once', (tester) async {
    final fake = FakeHandService(delay: const Duration(milliseconds: 100));
    await pumpQuickHand(tester, fake);

    stateOf(tester).debugSetHeroCards(['As', 'Kd']);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'CO'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Fold'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save Hand'));
    await tester.pump(); // _saving = true, service call in flight
    await tester.tap(find.widgetWithText(FilledButton, 'Saving…'),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(fake.saveCalls, equals(1));
  });

  testWidgets('session prefill locks game type and threads the session id',
      (tester) async {
    final fake = FakeHandService();
    await pumpQuickHand(tester, fake,
        prefilledSessionId: 'sess-1',
        prefilledStakes: '2/5',
        isTournamentSession: false);

    expect(find.text('Cash · from session'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);

    stateOf(tester).debugSetHeroCards(['As', 'Kd']);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'SB'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Fold'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Hand'));
    await tester.pumpAndSettle();

    expect(fake.capturedSessionId, equals('sess-1'));
    expect(fake.capturedSetup!.smallBlind, equals(2));
    expect(fake.capturedSetup!.bigBlind, equals(5));
  });

  testWidgets('tournament prefill whose stakes match a cash preset is saveable',
      (tester) async {
    // Regression: "1/2" is a cash preset, but for a tournament session it is a
    // blind level and must populate the SB/BB fields, not the preset selector.
    final fake = FakeHandService();
    await pumpQuickHand(tester, fake,
        prefilledSessionId: 'sess-1',
        prefilledStakes: '1/2',
        isTournamentSession: true);

    stateOf(tester).debugSetHeroCards(['As', 'Kd']);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'BTN'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Raise'));
    await tester.pump();

    // The blinds resolved from the prefill, so Save is enabled.
    final save = find.widgetWithText(FilledButton, 'Save Hand');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(fake.capturedIsTournament, isTrue);
    expect(fake.capturedSetup!.smallBlind, equals(1));
    expect(fake.capturedSetup!.bigBlind, equals(2));
  });

  testWidgets('cash prefill with currency symbols parses and is saveable',
      (tester) async {
    // Regression: a naive split('/') rejected "$2/$5"; the canonical parser
    // strips the currency symbols.
    final fake = FakeHandService();
    await pumpQuickHand(tester, fake,
        prefilledSessionId: 'sess-1',
        prefilledStakes: r'$2/$5',
        isTournamentSession: false);

    stateOf(tester).debugSetHeroCards(['As', 'Kd']);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'BTN'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Raise'));
    await tester.pump();

    final save = find.widgetWithText(FilledButton, 'Save Hand');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(fake.capturedSetup!.smallBlind, equals(2));
    expect(fake.capturedSetup!.bigBlind, equals(5));
  });

  group('back-gesture discard guard', () {
    // Pushed from a host so the system back gesture (handlePopRoute →
    // Navigator.maybePop → PopScope) has a route to pop back to.
    Future<void> pumpWithHost(WidgetTester tester, FakeHandService fake) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [handServiceProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => const QuickHandScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('pristine form pops on system back without a prompt',
        (tester) async {
      await pumpWithHost(tester, FakeHandService());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard hand?'), findsNothing);
      expect(find.byType(QuickHandScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('dirty form asks to discard; Cancel keeps it, Discard pops',
        (tester) async {
      await pumpWithHost(tester, FakeHandService());
      stateOf(tester).debugSetHeroCards(['As', 'Kd']);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard hand?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickHandScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickHandScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('dirty form confirms before switching to Full mode',
        (tester) async {
      final fake = FakeHandService();
      await pumpQuickHand(tester, fake);
      stateOf(tester).debugSetHeroCards(['As', 'Kd']);
      await tester.pump();

      await tester.tap(find.text('Full mode'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to Full mode?'), findsOneWidget);

      // Cancel keeps the quick form (and its state) intact.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickHandScreen), findsOneWidget);
    });
  });
}
