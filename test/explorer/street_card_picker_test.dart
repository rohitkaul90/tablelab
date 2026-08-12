// The runout picker's suit-isomorphism routing: an absent card whose stored
// suit-equivalent twin exists renders tappable (≡ badge) and reports the
// REPRESENTATIVE; truly dead cards (board / no twin) stay disabled.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/widgets/explorer/board_cards.dart';
import 'package:tablelab/widgets/explorer/street_card_picker.dart';

Finder _tile(String card) => find.ancestor(
      of: find.byWidgetPredicate((w) => w is CardGlyph && w.card == card),
      matching: find.byType(InkWell),
    );

void main() {
  // Monotone club flop — the d/h/s off-suits are one equivalence class.
  const flop = ['Ac', '7c', '6c'];

  Widget host({
    required Set<String> available,
    required void Function(String) onPick,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: StreetCardPicker(
            title: 'Pick the turn card',
            excluded: flop.toSet(),
            available: available,
            isoBoard: flop,
            onPick: onPick,
          ),
        ),
      );

  testWidgets('absent-but-equivalent card taps through to the stored twin',
      (tester) async {
    String? picked;
    await tester.pumpWidget(host(
      available: {'2d', 'Kd', 'Kc'},
      onPick: (c) => picked = c,
    ));
    // ≡ badges mark the routed twins (2h/2s → 2d, Kh/Ks → Kd).
    expect(find.text('≡'), findsNWidgets(4));

    await tester.tap(_tile('2s'));
    await tester.pump();
    expect(picked, '2d');
    // Transient equivalence hint.
    expect(find.text('2♠ ≡ 2♦ here — suits are interchangeable'),
        findsOneWidget);
    // Let the snackbar's auto-dismiss timer fire before the test tears down.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('stored card taps through unchanged, no hint', (tester) async {
    String? picked;
    await tester.pumpWidget(host(available: {'2d'}, onPick: (c) => picked = c));
    await tester.tap(_tile('2d'));
    await tester.pump();
    expect(picked, '2d');
    expect(find.textContaining('suits are interchangeable'), findsNothing);
  });

  testWidgets('truly dead cards stay disabled', (tester) async {
    String? picked;
    await tester.pumpWidget(host(available: {'2d'}, onPick: (c) => picked = c));
    // 2c: the flush suit is its own class with no stored member → disabled.
    await tester.tap(_tile('2c'));
    // Kh: no K stored in any equivalent suit → disabled.
    await tester.tap(_tile('Kh'));
    // Board card → disabled.
    await tester.tap(_tile('Ac'));
    await tester.pump();
    expect(picked, isNull);
  });

  group('cross-street pin semantics (PR #66)', () {
    // Flop Kc 9c 4d: h/s merge over the flop alone, so a turn pick of the
    // absent As routes to a stored Ah. A previously pinned river no longer
    // constrains a TURN pick — changing the turn CLEARS the pinned river, so
    // the call sites pass a FLOP-ONLY iso context (and don't exclude the
    // river card). A RIVER pick still carries the stored turn in [excluded].
    const flop = ['Kc', '9c', '4d'];

    Widget pinnedHost({
      required Set<String> excluded,
      required Set<String> available,
      required List<String> isoBoard,
      required void Function(String) onPick,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: StreetCardPicker(
              title: 'Pick the turn card',
              excluded: excluded,
              available: available,
              isoBoard: isoBoard,
              onPick: onPick,
            ),
          ),
        );

    testWidgets(
        'turn pick under flop-only context routes As even with a river '
        'pinned (the pin is about to be cleared)', (tester) async {
      String? picked;
      await tester.pumpWidget(pinnedHost(
        excluded: flop.toSet(), // NO river card — as if no river exists
        available: const {'Ah'},
        isoBoard: flop,
        onPick: (c) => picked = c,
      ));
      // As has a stored twin over the flop → ≡ badge, taps through to Ah.
      expect(find.text('≡'), findsOneWidget);
      await tester.tap(_tile('As'));
      await tester.pump();
      expect(picked, 'Ah');
      // Let the snackbar's auto-dismiss timer fire before teardown.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'river path: an excluded twin is removed from the routable targets',
        (tester) async {
      // Ah IS stored, but it's the pinned turn (excluded on a river pick) —
      // it cannot stand in for As, which then has no representative →
      // disabled.
      String? picked;
      await tester.pumpWidget(pinnedHost(
        excluded: {...flop, 'Ah'},
        available: const {'Ah'},
        isoBoard: flop,
        onPick: (c) => picked = c,
      ));
      expect(find.text('≡'), findsNothing);
      await tester.tap(_tile('As'));
      await tester.pump();
      expect(picked, isNull);
    });
  });
}
