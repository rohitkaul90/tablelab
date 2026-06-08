import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/providers/providers.dart';
import 'package:tablelab/services/ai_service.dart';
import 'package:tablelab/widgets/ai_usage_pill.dart';

Widget _wrap(List<Override> overrides, Widget child) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

Override _usage(AiUsage value) =>
    aiUsageProvider.overrideWith((ref) async => value);

void main() {
  testWidgets('renders nothing while usage is still loading', (tester) async {
    final never = Completer<AiUsage>(); // never completes
    await tester.pumpWidget(_wrap(
      [aiUsageProvider.overrideWith((ref) => never.future)],
      const AiUsagePill(kind: AiAnalysisKind.session),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('shows remaining free session analyses (5-limit)', (tester) async {
    await tester.pumpWidget(_wrap(
      [_usage(const AiUsage(session: 2, hand: 0, exempt: false))],
      const AiUsagePill(kind: AiAnalysisKind.session),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 free AI session analyses left today'),
        findsOneWidget);
  });

  testWidgets('uses singular phrasing when one analysis remains',
      (tester) async {
    await tester.pumpWidget(_wrap(
      [_usage(const AiUsage(session: 4, hand: 0, exempt: false))],
      const AiUsagePill(kind: AiAnalysisKind.session),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 free AI session analysis left today'),
        findsOneWidget);
  });

  testWidgets('shows limit-reached when the hand quota is exhausted',
      (tester) async {
    await tester.pumpWidget(_wrap(
      [_usage(const AiUsage(session: 0, hand: 20, exempt: false))],
      const AiUsagePill(kind: AiAnalysisKind.hand),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Daily AI hand limit reached'), findsOneWidget);
  });

  testWidgets('shows unlimited for an exempt account', (tester) async {
    await tester.pumpWidget(_wrap(
      [_usage(const AiUsage(session: 99, hand: 99, exempt: true))],
      const AiUsagePill(kind: AiAnalysisKind.session),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('unlimited'), findsOneWidget);
  });

  testWidgets('hand kind reflects the 20/day limit', (tester) async {
    await tester.pumpWidget(_wrap(
      [_usage(const AiUsage(session: 0, hand: 5, exempt: false))],
      const AiUsagePill(kind: AiAnalysisKind.hand),
    ));
    await tester.pumpAndSettle();
    // 20 - 5 = 15 remaining
    expect(find.textContaining('15 free AI hand analyses left today'),
        findsOneWidget);
  });
}
