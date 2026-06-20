import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/widgets/profile_avatar.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows initials when imageUrl is null', (tester) async {
    await tester.pumpWidget(_wrap(const ProfileAvatar(
      imageUrl: null,
      initials: 'RK',
      radius: 28,
      backgroundColor: Colors.green,
    )));
    expect(find.text('RK'), findsOneWidget);
  });

  testWidgets('shows initials when imageUrl is empty', (tester) async {
    await tester.pumpWidget(_wrap(const ProfileAvatar(
      imageUrl: '',
      initials: 'RK',
      radius: 28,
      backgroundColor: Colors.green,
    )));
    expect(find.text('RK'), findsOneWidget);
  });

  testWidgets('falls back to initials (no crash) when the network image fails',
      (tester) async {
    // NetworkImage requests fail in the test environment; the widget's
    // onBackgroundImageError must catch that and show initials instead of
    // letting the error propagate (the crash-issues-10 fix).
    await tester.pumpWidget(_wrap(const ProfileAvatar(
      imageUrl: 'https://lh3.googleusercontent.com/does-not-resolve',
      initials: 'RK',
      radius: 28,
      backgroundColor: Colors.green,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('RK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
