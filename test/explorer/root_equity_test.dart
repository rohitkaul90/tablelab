import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';
import 'package:tablelab/explorer/root_equity.dart';

/// The on-device equity MC must sample the range it FACES weighted by reach —
/// that's what lets the turn/river opponent curve render correctly (their range
/// is reach-skewed by earlier betting, unlike the uniform flop root).
void main() {
  List<int> board(String s) => [for (final t in s.split(' ')) parseCard(t)];

  // River board (no runout → deterministic showdown per villain draw).
  // Hero KhKd = trip kings: beats QcQd (trip queens), loses to AhAd (trip aces).
  final b = board('As Ks Qh 2c 7d');
  double heroEq(double qq, double aa) {
    final out = computeOppRangeEquities(OppRangeEquityPayload(
      hero: const [WeightedCombo(0, 'KhKd', 1.0)],
      villain: [
        WeightedCombo(0, 'QcQd', qq),
        WeightedCombo(1, 'AhAd', aa),
      ],
      board: b,
    ));
    return out.single.equity!;
  }

  test('villain range is sampled weighted by reach', () {
    expect(heroEq(1.0, 0.0), greaterThan(0.95)); // only the combo hero beats
    expect(heroEq(0.0, 1.0), lessThan(0.05)); // only the combo that beats hero
    final even = heroEq(1.0, 1.0);
    expect(even, closeTo(0.5, 0.15)); // 50/50 mix
    // Skewing reach toward the beatable combo raises hero equity.
    expect(heroEq(3.0, 1.0), greaterThan(even));
    expect(heroEq(1.0, 3.0), lessThan(even));
  });

  test('hero reach + comboId are carried onto the curve points', () {
    final out = computeOppRangeEquities(OppRangeEquityPayload(
      hero: const [WeightedCombo(5, 'KhKd', 0.42)],
      villain: const [WeightedCombo(0, 'QcQd', 1.0)],
      board: b,
    ));
    expect(out.single.comboId, 5);
    expect(out.single.reach, closeTo(0.42, 1e-9));
  });

  test('flop-root (uniform) path still computes sensible equities', () {
    final out = computeRootEquities(RootEquityPayload(
      heroCombos: const ['AhAd'], // set of aces on an A-high flop
      villainCombos: const ['KhKd', 'QhQd'],
      board: board('As 7c 2d'),
    ));
    expect(out, isNotEmpty);
    expect(out.single.equity, greaterThan(0.7));
  });
}
