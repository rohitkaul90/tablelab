import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/explorer/pack_source.dart';
import 'package:tablelab/widgets/explorer/board_picker_sheet.dart';

class _NullSource implements PackSource {
  @override
  Future<Uint8List> read(String relPath) async => Uint8List(0);
}

ExplorerSpotRef _spot(String flop, String spr) => ExplorerSpotRef(
      scenario: 'srp_late_v_bb',
      flop: flop,
      spr: spr,
      source: _NullSource(),
    );

/// The lazy board-picker sheet: spinner while the index loads, retryable
/// error state, filter chips + search over the loaded boards, and the
/// regime-fallback pick.
void main() {
  Widget host(BoardPickerSheet sheet) => MaterialApp(
        home: Scaffold(body: sheet),
      );

  testWidgets('spinner → data; search narrows; tap picks preferred spr',
      (tester) async {
    final completer = Completer<List<ExplorerSpotRef>>();
    ExplorerSpotRef? picked;
    await tester.pumpWidget(host(BoardPickerSheet(
      title: 'Solved boards',
      preferredSpr: 'deep',
      loadSpots: () => completer.future,
      onPick: (s) => picked = s,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete([
      _spot('Ks 9h 4c', 'medium'),
      _spot('Ks 9h 4c', 'deep'),
      _spot('7s 5s 2s', 'medium'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 boards'), findsOneWidget);
    expect(find.text('Ks 9h 4c'), findsOneWidget);
    expect(find.text('7s 5s 2s'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ks9');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 boards'), findsOneWidget);
    expect(find.text('7s 5s 2s'), findsNothing);

    await tester.tap(find.text('Ks 9h 4c'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.spr, 'deep'); // the preferred regime, not the first row
  });

  testWidgets('regime fallback: no spot at preferredSpr → the board\'s first',
      (tester) async {
    ExplorerSpotRef? picked;
    await tester.pumpWidget(host(BoardPickerSheet(
      title: 'Solved boards',
      preferredSpr: 'deep',
      loadSpots: () async => [_spot('7s 5s 2s', 'medium')],
      onPick: (s) => picked = s,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7s 5s 2s'));
    await tester.pumpAndSettle();
    expect(picked!.spr, 'medium');
  });

  testWidgets('filter chips narrow by texture facet', (tester) async {
    await tester.pumpWidget(host(BoardPickerSheet(
      title: 'Solved boards',
      loadSpots: () async => [
        _spot('Ks 9h 4c', 'medium'), // rainbow
        _spot('7s 5s 2s', 'medium'), // monotone
      ],
      onPick: (_) {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monotone'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 boards'), findsOneWidget);
    expect(find.text('Ks 9h 4c'), findsNothing);
    expect(find.text('7s 5s 2s'), findsOneWidget);
  });

  testWidgets('non-canonical suit spelling finds the stored board + iso hint',
      (tester) async {
    await tester.pumpWidget(host(BoardPickerSheet(
      title: 'Solved boards',
      loadSpots: () async => [
        _spot('7c 5c 2c', 'medium'), // canonical monotone
        _spot('Kc 9d 4h', 'medium'), // canonical rainbow
      ],
      onPick: (_) {},
    )));
    await tester.pumpAndSettle();

    // The user searches the spade spelling of the stored club board.
    await tester.enterText(find.byType(TextField), '7s5s2s');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 boards'), findsOneWidget);
    expect(find.text('7c 5c 2c'), findsOneWidget);
    expect(
      find.text('Showing 7♣5♣2♣ — same board as 7♠5♠2♠ '
          '(suits are interchangeable)'),
      findsOneWidget,
    );

    // Typing the stored spelling shows no redirect hint.
    await tester.enterText(find.byType(TextField), '7c5c2c');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 boards'), findsOneWidget);
    expect(find.textContaining('same board as'), findsNothing);
  });

  testWidgets('a malformed flop label renders a placeholder, not a crash',
      (tester) async {
    await tester.pumpWidget(host(BoardPickerSheet(
      title: 'Solved boards',
      loadSpots: () async => [
        _spot('garbage', 'medium'), // unparseable — deliberately still listed
        _spot('Ks 9h 4x', 'medium'), // bad suit token
        _spot('Ks 9h 4c', 'medium'),
      ],
      onPick: (_) {},
    )));
    await tester.pumpAndSettle(); // would throw here if CardGlyph RangeError'd
    expect(find.text('3 of 3 boards'), findsOneWidget);
    expect(find.text('garbage'), findsOneWidget);
    expect(find.text('?'), findsWidgets); // neutral placeholder glyphs
  });

  testWidgets('load failure → error state; Retry refetches', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(BoardPickerSheet(
      title: 'Solved boards',
      loadSpots: () async {
        calls++;
        if (calls == 1) throw StateError('index fetch failed');
        return [_spot('Ks 9h 4c', 'medium')];
      },
      onPick: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the board list"), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Ks 9h 4c'), findsOneWidget);
  });
}
