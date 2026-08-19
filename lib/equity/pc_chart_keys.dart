// App-context → PC-chart resolution for the weighted range library.
//
// The app names positions button-relative per table size (hand_model.dart
// positionLabels: 9-max = BTN,SB,BB,UTG,UTG+1,UTG+2,MP,HJ,CO); the PC library
// is 8-max canonical (UTG,UTG1,LJ,HJ,CO,BTN,SB,BB — see
// tool/solver/RANGE_MIGRATION_PLAN.md). This file owns the mapping between the
// two, exactly like chart_keys.dart owns it for the legacy binary presets.
//
// Seat mapping principle: LATE positions anchor. We walk backward from the
// button (BTN, CO, HJ, ...) in both vocabularies and clamp anything earlier
// than the PC ladder to UTG. This is also the fix for the old 6-max/9-max
// mislabel: a 6-max table's "UTG" is three-off-the-button and correctly
// resolves to PC's LJ, not the full-ring UTG chart.
//
// PURE Dart — no Flutter, no I/O.

import 'weighted_ranges.dart';

/// PC seats in action order (8-max).
const List<String> kPcSeats = [
  'UTG', 'UTG1', 'LJ', 'HJ', 'CO', 'BTN', 'SB', 'BB',
];

/// PC non-blind seats walking BACKWARD from the button.
const List<String> _pcFromButton = ['BTN', 'CO', 'HJ', 'LJ', 'UTG1', 'UTG'];

/// Maps an app position label (as produced by TableSetup.positionLabels /
/// positionName for [tableSeats]) to the PC 8-max seat whose chart applies.
///
/// Blinds map directly (the straddler defends like a BB, mirroring
/// chart_keys.posClass). Non-blind seats map by distance-from-button, clamped
/// to UTG for tables deeper than 8-handed.
String pcSeatFor(String appLabel, int tableSeats) {
  switch (appLabel) {
    case 'SB':
      return 'SB';
    case 'BB':
    case 'STR':
      return 'BB';
  }
  // Non-blind ladder for this table size, walking backward from the button.
  // App labels come from hand_model's tables: e.g. 9-max backward =
  // BTN, CO, HJ, MP, UTG+2, UTG+1, UTG.
  final ladder = _appFromButton(tableSeats);
  final idx = ladder.indexOf(appLabel);
  if (idx < 0) return 'UTG'; // exotic label (P7, ...): earliest is safest
  return idx < _pcFromButton.length ? _pcFromButton[idx] : 'UTG';
}

List<String> _appFromButton(int seats) {
  // Mirrors hand_model.dart _positionLabels, non-blind seats only, reversed
  // into backward-from-button order.
  const tables = {
    2: ['BTN'],
    3: ['BTN'],
    4: ['BTN', 'UTG'],
    5: ['BTN', 'CO', 'UTG'],
    6: ['BTN', 'CO', 'HJ', 'UTG'],
    7: ['BTN', 'CO', 'HJ', 'MP', 'UTG'],
    8: ['BTN', 'CO', 'HJ', 'MP', 'UTG+1', 'UTG'],
    9: ['BTN', 'CO', 'HJ', 'MP', 'UTG+2', 'UTG+1', 'UTG'],
  };
  return tables[seats] ?? tables[9]!;
}

/// The situation-node id for a hero facing [facing] (mirrors the normalized
/// dataset's node vocabulary).
class PcNode {
  static const rfi = 'rfi';
  static const vsOpen = 'vs_open';
  static const vs3bet = 'vs_3bet';
  static const vs4bet = 'vs_4bet';
  static const vsRaiseCall = 'vs_raise_call';
  static const vsLimp = 'vs_limp';
}

/// Resolves a chart for an app-level preflop spot.
///
/// [heroLabel]/[openerLabel] are app position labels for [tableSeats];
/// [effectiveBb] snaps to the nearest available depth in the library
/// (cash: 100/200; mtt: 80/50/30/20/12 in the bundled asset).
WeightedChart? resolvePcChart(
  PcRangeLibrary lib, {
  required bool tournament,
  required int tableSeats,
  required num effectiveBb,
  required String heroLabel,
  required String node,
  String? openerLabel,
  String? callerLabel,
}) {
  final game = tournament ? 'mtt' : 'cash';
  final hero = pcSeatFor(heroLabel, tableSeats);
  List<String>? villains;
  if (openerLabel != null) {
    final opener = pcSeatFor(openerLabel, tableSeats);
    villains = callerLabel == null
        ? [opener]
        : [opener, pcSeatFor(callerLabel, tableSeats)];
    // A hero/villain collision means the seat mapping collapsed two distinct
    // app seats onto one PC seat (deep full-ring tables clamp to UTG). Shift
    // the villain one seat earlier so the lookup stays coherent.
    if (villains.first == hero) {
      final i = kPcSeats.indexOf(villains.first);
      if (i > 0) villains[0] = kPcSeats[i - 1];
    }
  }
  return lib.find(
    game: game,
    bbs: effectiveBb,
    hero: hero,
    node: node,
    villains: villains,
  );
}

/// Binary "does hero open this hand?" view over the PC RFI chart — the
/// drop-in replacement for legacy `presetByKey[rfiKey(...)]` membership tests.
/// A hand counts as opening when it raises at least [threshold] of the time.
Set<String>? pcRfiHands(
  PcRangeLibrary lib, {
  required bool tournament,
  required int tableSeats,
  required num effectiveBb,
  required String heroLabel,
  double threshold = 0.5,
}) {
  final chart = resolvePcChart(
    lib,
    tournament: tournament,
    tableSeats: tableSeats,
    effectiveBb: effectiveBb,
    heroLabel: heroLabel,
    node: PcNode.rfi,
  );
  if (chart == null) return null;
  return chart.binaryHands(chart.raiseFreq, threshold: threshold);
}
