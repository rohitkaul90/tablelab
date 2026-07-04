import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/widgets/explorer/action_colors.dart';

/// Bet/raise labels must read as a % of the pot (the solver's normalized chip
/// amount is meaningless once the pot shows in bb), and a shove collapses to
/// 'All-in'.
void main() {
  test('bet sizes render as a percent of the pot', () {
    // Flop root: pot 10, stack 40 behind.
    expect(actionSizeLabel('BET 3', potBefore: 10, behind: 40), 'Bet 30%');
    expect(actionSizeLabel('BET 8', potBefore: 10, behind: 40), 'Bet 80%');
    expect(actionSizeLabel('BET 10.000000', potBefore: 10, behind: 40),
        'Bet 100%');
    expect(actionSizeLabel('RAISE 22.5', potBefore: 15, behind: 40),
        'Raise 150%');
  });

  test('a bet/raise for everything behind reads All-in', () {
    expect(actionSizeLabel('BET 40', potBefore: 10, behind: 40), 'All-in');
    expect(actionSizeLabel('BET 40.000000', potBefore: 10, behind: 40),
        'All-in');
    expect(actionSizeLabel('RAISE 40', potBefore: 10, behind: 40), 'All-in');
    // Just under the stack is a real (over)bet, not a shove.
    expect(actionSizeLabel('BET 39.9', potBefore: 10, behind: 40), 'Bet 399%');
  });

  test('non-sized actions fall back to the plain label', () {
    expect(actionSizeLabel('CHECK', potBefore: 10, behind: 40), 'Check');
    expect(actionSizeLabel('CALL', potBefore: 10, behind: 40), 'Call');
    expect(actionSizeLabel('FOLD', potBefore: 10, behind: 40), 'Fold');
    // No pot info → don't fabricate a percent.
    expect(actionSizeLabel('BET 8', potBefore: 0, behind: 40), 'Bet 8');
  });
}
