// GTO Explorer — PREFLOP trail logic: decisions built from the bundled GTO
// preset charts (gto_ranges.dart via chart_keys.dart — the SAME triple-use
// presets the coaching villain model and the calculators read).
//
// Honesty note baked into the model: presets are RANGES, not mixed solver
// frequencies — a hand is in or out (overlaps resolve by precedence: 4-bet >
// call-3-bet, 3-bet > call). The action shares are each range's share OF ALL
// HANDS ("% of hands"), never a per-hand GTO frequency. Pure Dart, unit-tested.

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/chart_keys.dart';

import 'grid_aggregation.dart';

/// 6-max seats in action order.
const List<String> kTrailPositions = ['UTG', 'HJ', 'CO', 'BTN', 'SB', 'BB'];

/// One decision point on the trail: an actor, its available actions, and the
/// (mutually exclusive) hand set per action. The last action is always the
/// implicit remainder (fold — or check where folding is impossible).
class PreflopDecision {
  final String actorLabel; // 'BTN'
  final List<String> actions; // display labels, e.g. ['Raise', 'Fold']
  final List<Set<String>> ranges; // hand notations per action

  PreflopDecision(this.actorLabel, this.actions, this.ranges)
      : assert(actions.length == ranges.length);

  /// Combos per action (pair 6 / suited 4 / offsuit 12; total 1326).
  List<int> get comboCounts =>
      [for (final r in ranges) r.fold(0, (s, h) => s + _combosOf(h))];

  /// Share of ALL hands per action (sums to 1).
  List<double> get shares =>
      [for (final c in comboCounts) c / 1326.0];
}

int _combosOf(String hand) {
  final (row, col) = handToCell(hand);
  return cellComboCount(row, col);
}

Set<String> _preset(String? key) =>
    key == null ? const {} : (presetByKey[key] ?? const {});

/// All 169 hand notations.
Set<String> _allHands() => {
      for (var row = 0; row < 13; row++)
        for (var col = 0; col < 13; col++) cellToHand(row, col),
    };

/// The opener's RFI decision, or null for a seat with no opening chart (BB).
PreflopDecision? openerDecision(String label, {required bool trn}) {
  final key = rfiKey(label, trn);
  if (key == null) return null;
  final raise = _preset(key);
  if (raise.isEmpty) return null;
  return PreflopDecision(
      label, ['Raise', 'Fold'], [raise, _allHands().difference(raise)]);
}

/// A responder's decision vs the open: 3-bet > call precedence; fold = rest.
PreflopDecision responderDecision(String responderLabel, String openerLabel,
    {required bool trn}) {
  final pc = posClass(responderLabel);
  final bucket = openerBucketForLabel(openerLabel);
  final threeBet = _preset(threeBetKey(pc, bucket, trn));
  final call =
      _preset(callKey(pc, bucket, openerLabel, trn)).difference(threeBet);
  final fold = _allHands().difference(threeBet).difference(call);
  return PreflopDecision(
      responderLabel, ['3-bet', 'Call', 'Fold'], [threeBet, call, fold]);
}

/// The opener's decision facing [threeBetterLabel]'s 3-bet: 4-bet (value) >
/// call; fold = rest. Scoped WITHIN the opener's own RFI range. The
/// continue-chart side depends on who 3-bet: a blind 3-bettor leaves the
/// opener IN position postflop, any other seat leaves them out of position.
PreflopDecision openerVs3BetDecision(String openerLabel,
    String threeBetterLabel, {required bool trn}) {
  final open = _preset(rfiKey(openerLabel, trn));
  final openerInPosition =
      threeBetterLabel == 'SB' || threeBetterLabel == 'BB';
  final fourBet = _preset(fourBetKey(trn)).intersection(open);
  final call = _preset(call3BetKey(openerInPosition ? 'ip' : 'oop', trn))
      .intersection(open)
      .difference(fourBet);
  final fold = open.difference(fourBet).difference(call);
  return PreflopDecision(
      openerLabel, ['4-bet', 'Call', 'Fold'], [fourBet, call, fold]);
}

/// The SOLVED postflop scenario a completed trail maps to, or null. Mirrors
/// the live gate (villain_range._deriveScenarioKey): IP openers by bucket vs
/// a BB caller; BTN-open → BB-3-bet → BTN-call; SB opener excluded (opens
/// OOP); solved scenarios are cash-only.
String? trailScenarioKey({
  required String opener,
  required String? responder,
  required String? responderAction,
  required String? openerResponse,
  required bool trn,
}) {
  if (trn) return null;
  if (responder != 'BB') return null;
  if (responderAction == 'Call') {
    if (opener == 'SB') return null;
    return switch (openerBucketForLabel(opener)) {
      'late' => 'srp_late_v_bb',
      'middle' => 'srp_middle_v_bb',
      _ => 'srp_early_v_bb',
    };
  }
  if (responderAction == '3-bet' &&
      openerResponse == 'Call' &&
      opener == 'BTN') {
    return '3bp_bb_v_btn';
  }
  return null;
}

/// Build the 13×13 grid cells for a decision: each cell is one hand notation
/// with a ONE-HOT action mix (a preset either contains the hand or not) —
/// rendered by the same StrategyGrid/filter mechanics as postflop. For a
/// responder/vs-3-bet decision the "universe" may be a subrange (the opener's
/// range); hands outside every action set render absent (null).
List<List<GridCellAgg?>> preflopGridCells(PreflopDecision d) {
  return List.generate(13, (row) {
    return List.generate(13, (col) {
      final hand = cellToHand(row, col);
      final maxCombos = cellComboCount(row, col);
      var actionIdx = -1;
      for (var a = 0; a < d.ranges.length; a++) {
        if (d.ranges[a].contains(hand)) {
          actionIdx = a;
          break; // precedence = list order
        }
      }
      if (actionIdx < 0) return null;
      return GridCellAgg(
        hand: hand,
        comboCount: maxCombos,
        maxCombos: maxCombos,
        reach: maxCombos.toDouble(),
        freqs: [
          for (var a = 0; a < d.actions.length; a++)
            a == actionIdx ? 1.0 : 0.0,
        ],
        equity: null,
        combos: const [],
        dominantClass: null,
      );
    });
  });
}
