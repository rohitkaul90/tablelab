// Equity-calculator presets derived from the PC weighted range library.
//
// The range editor's 13x13 matrix is binary, so each preset is a thresholded
// view of a weighted chart (a hand is "in" when it takes the preset's action
// at least half the time). These REPLACE the legacy hand-authored presets in
// the picker UI once the library loads — the legacy kGtoPresets stay in code
// for the villain-range model until the Phase B cutover
// (tool/solver/RANGE_MIGRATION_PLAN.md).
//
// PURE Dart — no Flutter, no I/O.

import 'gto_ranges.dart' show GtoPreset;
import 'weighted_ranges.dart';

const _seatLabels = {
  'UTG': 'UTG',
  'UTG1': 'UTG+1',
  'LJ': 'LJ',
  'HJ': 'HJ',
  'CO': 'CO',
  'BTN': 'BTN',
  'SB': 'SB',
};

/// Builds the picker preset list from the loaded library. Categories mirror
/// the legacy picker's shape (opens, defends, 3-bets, tournament opens) at a
/// similar total count, sourced from the cash 8-max 100/200bb and MTT 30bb
/// slices.
List<GtoPreset> pcEquityPresets(PcRangeLibrary lib) {
  final out = <GtoPreset>[];

  void addRfi(String category, String game, num bbs, {String? labelSuffix}) {
    for (final e in _seatLabels.entries) {
      final ch =
          lib.find(game: game, bbs: bbs, hero: e.key, node: 'rfi');
      if (ch == null || ch.bbs != bbs) continue; // exact depth only
      final hands = ch.binaryHands(ch.raiseFreq);
      if (hands.isEmpty) continue;
      out.add(GtoPreset(
        key: 'pc_${game}_${bbs}_rfi_${e.key}',
        label: '${e.value} Open${labelSuffix ?? ''}',
        category: category,
        hands: hands,
      ));
    }
  }

  addRfi('Open — Cash 100bb', 'cash', 100);
  addRfi('Open — Cash 200bb', 'cash', 200);
  addRfi('Open — MTT 30bb', 'mtt', 30);

  for (final e in _seatLabels.entries) {
    final ch = lib.find(
        game: 'cash',
        bbs: 100,
        hero: 'BB',
        node: 'vs_open',
        villains: [e.key]);
    if (ch == null || ch.bbs != 100) continue; // exact depth only
    final defend = ch.binaryHands(ch.continueFreq);
    if (defend.isNotEmpty) {
      out.add(GtoPreset(
        key: 'pc_cash_100_bbdef_${e.key}',
        label: 'BB Defend vs ${e.value}',
        category: 'BB Defend — Cash 100bb',
        hands: defend,
      ));
    }
    final threeBet = ch.binaryHands(ch.raiseFreq);
    if (threeBet.isNotEmpty) {
      out.add(GtoPreset(
        key: 'pc_cash_100_bb3b_${e.key}',
        label: 'BB 3-Bet vs ${e.value}',
        category: 'BB 3-Bet — Cash 100bb',
        hands: threeBet,
      ));
    }
  }

  return out;
}
