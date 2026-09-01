import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/models/session_model.dart';
import 'package:tablelab/providers/providers.dart';
import 'package:tablelab/screens/hand_input/hand_input_screen.dart';

/// Back-gesture discard guard for the full wizard: a dirty in-progress hand
/// must not be silently discarded by the system back gesture, while a pristine
/// setup screen pops freely (guards the PopScope in HandInputScreen._build).
void main() {
  // Pushed from a host so the system back gesture (handlePopRoute →
  // Navigator.maybePop → PopScope) has a route to pop back to. The
  // sessionsProvider override keeps the setup step's SessionPickerTile off
  // Supabase.
  Future<void> pumpWizard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionsProvider.overrideWith((ref) async => <SessionModel>[]),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const HandInputScreen()),
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

  HandInputScreenState stateOf(WidgetTester tester) =>
      tester.state<HandInputScreenState>(find.byType(HandInputScreen));

  testWidgets('pristine setup pops on system back without a prompt',
      (tester) async {
    await pumpWizard(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Discard hand?'), findsNothing);
    expect(find.byType(HandInputScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('AppBar close on a pristine setup pops without a prompt',
      (tester) async {
    await pumpWizard(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Discard hand?'), findsNothing);
    expect(find.byType(HandInputScreen), findsNothing);
  });

  testWidgets('typed setup work (player name) arms the back guard',
      (tester) async {
    // Regression: the setup step's typed fields (names/stacks/blinds) didn't
    // count as dirty, so a back gesture silently discarded them.
    await pumpWizard(tester);

    await tester.enterText(find.byType(TextField).first, 'Bob');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard hand?'), findsOneWidget);
    expect(find.byType(HandInputScreen), findsOneWidget);
  });

  testWidgets('hero cards picked → back asks to discard; Cancel keeps it, Discard pops',
      (tester) async {
    await pumpWizard(tester);
    stateOf(tester).debugSetHeroCards(['As', 'Kd']);
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard hand?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(HandInputScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(HandInputScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
