import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/gto_ranges.dart' show GtoPreset;
import 'package:tablelab/equity/pc_equity_presets.dart';
import 'package:tablelab/equity/weighted_ranges.dart';

void main() {
  late List<GtoPreset> presets;
  late PcRangeLibrary lib;

  setUpAll(() {
    lib = PcRangeLibrary.fromJsonString(
        File('assets/pc_ranges.json').readAsStringSync());
    presets = pcEquityPresets(lib);
  });

  test('builds the expected categories with unique keys', () {
    final categories = presets.map((p) => p.category).toSet();
    expect(
        categories,
        containsAll([
          'Open — Cash 100bb',
          'Open — Cash 200bb',
          'Open — MTT 30bb',
          'BB Defend — Cash 100bb',
          'BB 3-Bet — Cash 100bb',
        ]));
    final keys = presets.map((p) => p.key).toList();
    expect(keys.toSet().length, keys.length);
    // 7 opens x 3 slices + 7 defends + 7 3-bets.
    expect(presets.length, 35);
  });

  test('BTN open preset carries the ~40% chart width', () {
    final btn = presets.firstWhere((p) => p.key == 'pc_cash_100_rfi_BTN');
    int combos(String h) =>
        h.length == 2 ? 6 : (h.endsWith('s') ? 4 : 12);
    final share =
        btn.hands.fold<int>(0, (s, h) => s + combos(h)) / 1326 * 100;
    expect(share, inInclusiveRange(33, 47));
    expect(btn.hands, contains('A2s'));
    expect(btn.hands, isNot(contains('72o')));
  });

  test('BB defend preset includes every audit-flagged hand', () {
    final def = presets.firstWhere((p) => p.key == 'pc_cash_100_bbdef_BTN');
    for (final h in ['TT', '99', 'KJs', 'KTs', 'KQo', 'AJo']) {
      expect(def.hands, contains(h), reason: h);
    }
    final threeBet =
        presets.firstWhere((p) => p.key == 'pc_cash_100_bb3b_BTN');
    expect(threeBet.hands, contains('TT')); // 3-bets 100% in the chart
    expect(threeBet.hands, isNot(contains('72o')));
  });
}
