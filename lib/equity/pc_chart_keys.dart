// App-context → PC-chart resolution for the weighted range library.
//
// The app names positions button-relative per table size
// (TableSetup.positionLabels — the single source of the ladder; this file
// deliberately DERIVES from it instead of re-forking the table, per the
// CLAUDE.md don't-re-fork rule). The PC library is 8-max canonical
// (UTG, UTG1, LJ, HJ, CO, BTN, SB, BB) plus a heads-up table — see
// tool/solver/RANGE_MIGRATION_PLAN.md.
//
// Seat mapping principle: LATE positions anchor. We walk backward from the
// button (BTN, CO, HJ, ...) in both vocabularies and clamp anything earlier
// than the PC ladder to UTG. This is also the fix for the old 6-max/9-max
// mislabel: a 6-max table's "UTG" is three-off-the-button and correctly
// resolves to PC's LJ, not the full-ring UTG chart. When clamping collides
// two distinct app seats onto one PC seat, the LATER-ACTING participant is
// shifted one PC seat later so hero and villains stay distinct (a hero
// responding to an open acts after the opener; a squeeze caller acts after
// the raiser).
//
// PURE Dart — no Flutter, no I/O.

import '../models/hand_model.dart' show TableSetup;
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
/// Role matters for the straddler, who is best understood as a THIRD BLIND:
/// they post dark, act last preflop, and close the action like a BB — so
/// defending, STR maps to BB (mirrors chart_keys.posClass). When the straddler
/// RAISES (the straddle-option raise over callers) there is no true chart in a
/// no-straddle library; we model them as an SB raiser — the widest blind-
/// aggressor chart available — because range WIDTH is what chart choice feeds
/// (a straddle-option raise is far wider than a UTG open, and postflop
/// position is derived independently from action order by villain_range, so
/// the chart's positional label doesn't leak into EQR). Owner-reviewed
/// decision 2026-08-19; the earlier 'UTG opener' mapping overstated the
/// straddler's strength.
String pcSeatFor(String appLabel, int tableSeats, {bool aggressor = false}) {
  switch (appLabel) {
    case 'SB':
      return 'SB';
    case 'BB':
      return 'BB';
    case 'STR':
      return aggressor ? 'SB' : 'BB';
  }
  final ladder = _appFromButton(tableSeats);
  final idx = ladder.indexOf(appLabel);
  if (idx < 0) return 'UTG'; // exotic label (P7, ...): earliest is safest
  return idx < _pcFromButton.length ? _pcFromButton[idx] : 'UTG';
}

/// Non-blind app labels for [seats], walking backward from the button —
/// derived from TableSetup.positionLabels ([BTN, SB, BB, ...ascending]) so the
/// ladder has exactly one source of truth.
List<String> _appFromButton(int seats) {
  final labels = TableSetup.positionLabels(seats);
  return [labels.first, ...labels.skip(3).toList().reversed];
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

/// Shifts a PC seat one step later in action order, staying in the non-blind
/// zone (UTG → UTG1 → LJ → HJ → CO → BTN). Returns the input at the cap.
String _oneSeatLater(String pcSeat) {
  final i = _pcFromButton.indexOf(pcSeat);
  return i <= 0 ? pcSeat : _pcFromButton[i - 1];
}

/// Resolves a chart for an app-level preflop spot.
///
/// [heroLabel]/[openerLabel]/[callerLabel] are app position labels for
/// [tableSeats]; [effectiveBb] snaps to the nearest available depth.
/// Heads-up tables (2 seats) route to the PC HU charts (app BTN posts the SB
/// heads-up → PC 'SB'). 3-handed tables return null — the library has no
/// 3-max charts and a full-ring chart would be confidently wrong (review
/// finding); callers must handle null anyway.
/// [facingAllIn] disambiguates same-node sequence variants (facing a 3-bet
/// JAM vs a sized 3-bet) — see PcRangeLibrary.find.
WeightedChart? resolvePcChart(
  PcRangeLibrary lib, {
  required bool tournament,
  required int tableSeats,
  required num effectiveBb,
  required String heroLabel,
  required String node,
  String? openerLabel,
  String? callerLabel,
  bool? facingAllIn,
}) {
  final game = tournament ? 'mtt' : 'cash';
  if (tableSeats == 2) {
    // Heads-up: the button IS the small blind.
    String hu(String l) => l == 'BTN' ? 'SB' : l == 'STR' ? 'BB' : l;
    return lib.find(
      game: game,
      table: 'hu',
      bbs: effectiveBb,
      hero: hu(heroLabel),
      node: node,
      villains: openerLabel == null ? null : [hu(openerLabel)],
      facingAllIn: facingAllIn,
    );
  }
  if (tableSeats == 3) return null;

  var hero = pcSeatFor(heroLabel, tableSeats);
  List<String>? villains;
  if (openerLabel != null) {
    var opener = pcSeatFor(openerLabel, tableSeats, aggressor: true);
    String? caller = callerLabel == null
        ? null
        : pcSeatFor(callerLabel, tableSeats, aggressor: true);
    // Clamping can collapse distinct app seats onto one PC seat (deep
    // full-ring tables squeeze UTG/UTG+1 together). Restore distinctness by
    // shifting the LATER-ACTING participant later: the caller acts after the
    // opener, and a responding hero acts after both. Each shift is bounded by
    // the ladder cap, so the loop terminates.
    if (caller != null && caller == opener) caller = _oneSeatLater(caller);
    for (var guard = 0;
        guard < kPcSeats.length &&
            hero != 'SB' &&
            hero != 'BB' &&
            (hero == opener || hero == caller);
        guard++) {
      final shifted = _oneSeatLater(hero);
      if (shifted == hero) break; // capped at BTN: give up shifting
      hero = shifted;
    }
    villains = caller == null ? [opener] : [opener, caller];
  }
  return lib.find(
    game: game,
    bbs: effectiveBb,
    hero: hero,
    node: node,
    villains: villains,
    facingAllIn: facingAllIn,
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
