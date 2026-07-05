import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/widgets/explorer/action_colors.dart';

/// Bet/raise labels must read as a % of the pot (the solver's normalized chip
/// amount is meaningless once the pot shows in bb), and a shove collapses to
/// 'All-in'.
void main() {
  test('bet sizes render as a percent of the pot', () {
    // Flop root: pot 10, no bet to call.
    expect(actionSizeLabel('BET 3', potBefore: 10, toCall: 0, behind: 40),
        'Bet 30%');
    expect(actionSizeLabel('BET 8', potBefore: 10, toCall: 0, behind: 40),
        'Bet 80%');
    expect(
        actionSizeLabel('BET 10.000000', potBefore: 10, toCall: 0, behind: 40),
        'Bet 100%');
  });

  test('raise sizes net out the call (chips beyond the call, over pot-after)',
      () {
    // Facing a bet of 5 into a pot of 15; a pot-sized raise-TO 25 = 100%,
    // NOT raiseTo/potBefore (which would misread 167%).
    expect(actionSizeLabel('RAISE 25', potBefore: 15, toCall: 5, behind: 100),
        'Raise 100%');
    // A min-ish raise-to 15 puts 10 beyond the call into a 20 pot = 50%.
    expect(actionSizeLabel('RAISE 15', potBefore: 15, toCall: 5, behind: 100),
        'Raise 50%');
  });

  test('a bet/raise for everything behind reads All-in', () {
    expect(
        actionSizeLabel('BET 40', potBefore: 10, toCall: 0, behind: 40),
        'All-in');
    expect(actionSizeLabel('RAISE 40', potBefore: 10, toCall: 5, behind: 40),
        'All-in');
  });

  test('non-sized actions fall back to the plain label', () {
    expect(
        actionSizeLabel('CHECK', potBefore: 10, toCall: 0, behind: 40), 'Check');
    expect(
        actionSizeLabel('CALL', potBefore: 10, toCall: 5, behind: 40), 'Call');
    expect(
        actionSizeLabel('FOLD', potBefore: 10, toCall: 0, behind: 40), 'Fold');
    // No pot info → don't fabricate a percent.
    expect(
        actionSizeLabel('BET 8', potBefore: 0, toCall: 0, behind: 40), 'Bet 8');
  });
}
