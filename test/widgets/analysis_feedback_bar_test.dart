import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/widgets/ai/analysis_feedback_bar.dart';

void main() {
  testWidgets('tapping thumbs-up rates once and updates the label',
      (tester) async {
    final ratings = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisFeedbackBar(onRate: (r) async => ratings.add(r)),
      ),
    ));

    expect(find.text('Was this analysis helpful?'), findsOneWidget);
    await tester.tap(find.byTooltip('Helpful'));
    await tester.pumpAndSettle();

    expect(ratings, [1]);
    expect(find.text('Thanks for the feedback!'), findsOneWidget);
  });

  testWidgets('re-tapping the same rating does not rate again',
      (tester) async {
    final ratings = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisFeedbackBar(onRate: (r) async => ratings.add(r)),
      ),
    ));

    await tester.tap(find.byTooltip('Helpful'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Helpful'));
    await tester.pumpAndSettle();

    expect(ratings, [1]);
  });

  testWidgets('rapid taps while saving are guarded', (tester) async {
    final ratings = <int>[];
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisFeedbackBar(onRate: (r) async {
          ratings.add(r);
          await gate.future;
        }),
      ),
    ));

    await tester.tap(find.byTooltip('Helpful'));
    await tester.pump();
    await tester.tap(find.byTooltip('Not helpful')); // ignored while saving
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(ratings, [1]);
  });

  testWidgets('a failed save reverts the selection', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisFeedbackBar(onRate: (r) async => throw Exception('rls')),
      ),
    ));

    await tester.tap(find.byTooltip('Helpful'));
    await tester.pumpAndSettle();

    expect(find.text('Was this analysis helpful?'), findsOneWidget);
  });
}
