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

/// Flop pot in BIG BLINDS per solved scenario — the anchor that maps the
/// solver's normalized chip scale (flop pot pinned to pot0 = 10) back to bb.
/// SRP = open 2.5x + BB call + dead SB (5.5bb); the 3-bet pot = BTN open, BB
/// 3-bet to 11, BTN call (22.5bb). Mirrors tool/solver freq_grid.dart
/// kScenarios; a scenario absent here (a future hosted pack) simply shows no bb.
const Map<String, double> kScenarioFlopPotBB = {
  'srp_late_v_bb': 5.5,
  'srp_early_v_bb': 5.5,
  'srp_middle_v_bb': 5.5,
  '3bp_bb_v_btn': 22.5,
};

/// bb per normalized pack unit for [scenario] (flop pot is pinned to [pot0], so
/// one unit = flopPotBB/pot0 bb). Null when the scenario has no bb anchor.
double? bbPerUnit(String scenario, double pot0) {
  final potBB = kScenarioFlopPotBB[scenario];
  if (potBB == null || pot0 <= 0) return null;
  return potBB / pot0;
}

/// Approximate STARTING stack in bb for each solved SPR regime — the solver's
/// design intent (short / mid / deep-cash). Shown in the settings depth picker
/// (and used to order it) INSTEAD of the raw regime name. Approximate: the pack
/// buckets by SPR, so 'deep' reads ~100bb even though the flop 'Behind' lands a
/// touch lower. Keys ordered shallowest→deepest. Mirrors freq_grid.dart's
/// sprReps commentary.
const Map<String, Map<String, int>> kScenarioDepthStartBB = {
  'srp_late_v_bb': {'shallow': 20, 'medium': 40, 'deep': 100},
  'srp_early_v_bb': {'shallow': 20, 'medium': 40, 'deep': 100},
  'srp_middle_v_bb': {'shallow': 20, 'medium': 40, 'deep': 100},
  '3bp_bb_v_btn': {'committed': 30, 'shallow': 60, 'medium': 100},
};

/// The bb depth label for a scenario + SPR regime, e.g. '~100bb'; falls back to
/// the raw regime name for a scenario with no bb mapping (future hosted packs).
String depthLabelBB(String scenario, String regime) {
  final bb = kScenarioDepthStartBB[scenario]?[regime];
  return bb != null ? '~${bb}bb' : regime;
}

/// The preflop betting sizes (in bb) the strip models — matched so the final
/// preflop pot equals the scenario's [kScenarioFlopPotBB] anchor (open 2.5x +
/// BB call = 5.5bb; + BB 3-bet 11 + call = 22.5bb).
const double kSbBlind = 0.5;
const double kBbBlind = 1.0;
const double kOpenToBB = 2.5;
const double kThreeBetToBB = 11.0;

double _postedBlind(String seat) => switch (seat) {
      'SB' => kSbBlind,
      'BB' => kBbBlind,
      _ => 0.0,
    };

/// The per-player preflop investment (bb) that brings the pot to the scenario's
/// flop anchor — each of the two players in a heads-up pot puts in this much
/// (SRP 2.5, 3-bet pot 11). Derived from the flop pot minus the dead SB.
double? perPlayerPreflopInvestBB(String scenario) {
  final potBB = kScenarioFlopPotBB[scenario];
  return potBB == null ? null : (potBB - kSbBlind) / 2;
}

/// Effective (remaining) stack in bb going INTO [seat]'s decision, given the
/// deep starting stack [startEff]. Each seat box is that seat's FIRST preflop
/// decision, so only its posted blind is in the pot yet.
double preflopEffStackBB(String seat, double startEff) =>
    startEff - _postedBlind(seat);

/// The opener's remaining stack in bb going into its vs-3-bet decision — its
/// open (2.5x) is already committed.
double preflopEffStackBBVs3Bet(double startEff) => startEff - kOpenToBB;

/// One decision point on the trail: an actor, its available actions, and the
/// (mutually exclusive) hand set per action. The last action is always the
/// implicit remainder (fold — or check where folding is impossible).
class PreflopDecision {
  final String actorLabel; // 'BTN'
  final List<String> actions; // display labels, e.g. ['Raise', 'Fold']
  final List<Set<String>> ranges; // hand notations per action

  PreflopDecision(this.actorLabel, this.actions, this.ranges)
      : assert(actions.length == ranges.length);

  /// Combos per action (pair 6 / suited 4 / offsuit 12).
  List<int> get comboCounts =>
      [for (final r in ranges) r.fold(0, (s, h) => s + _combosOf(h))];

  /// Share per action of the DECISION'S OWN universe (sums to 1). For the
  /// opener/responder that universe is all 1326 combos; for the vs-3-bet
  /// decision it is the opener's opened range — dividing by 1326 there
  /// understated every frequency by ~4× (review finding).
  List<double> get shares {
    final total = comboCounts.fold(0, (a, b) => a + b);
    return [for (final c in comboCounts) total == 0 ? 0.0 : c / total];
  }
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

/// The preflop trail's state: who opened, who responded (and how), and the
/// opener's answer to a 3-bet. Immutable; transitions reset everything
/// downstream of the change (a new opener voids the old response, etc.).
class PreflopTrail {
  final bool trn;
  final String? opener;
  final String? responder;
  final String? responderAction; // 'Call' | '3-bet'
  final String? openerResponse; // 'Call' | '4-bet' (only after a 3-bet)

  const PreflopTrail({
    this.trn = false,
    this.opener,
    this.responder,
    this.responderAction,
    this.openerResponse,
  });

  PreflopTrail withTrn(bool v) => PreflopTrail(trn: v);

  /// Flip cash/tournament while KEEPING the current line (the gear-menu toggle,
  /// which should not blow away the seats the user already built — unlike
  /// [withTrn], which resets the whole trail).
  PreflopTrail withTrnKeeping(bool v) => PreflopTrail(
        trn: v,
        opener: opener,
        responder: responder,
        responderAction: responderAction,
        openerResponse: openerResponse,
      );

  PreflopTrail withOpener(String pos) => PreflopTrail(trn: trn, opener: pos);

  PreflopTrail withResponse(String pos, String action) => PreflopTrail(
      trn: trn, opener: opener, responder: pos, responderAction: action);

  PreflopTrail withOpenerResponse(String action) => PreflopTrail(
      trn: trn,
      opener: opener,
      responder: responder,
      responderAction: responderAction,
      openerResponse: action);

  PreflopTrail reset() => PreflopTrail(trn: trn);

  /// Decision steps that exist so far: 0 = opener's open, 1 = the response,
  /// 2 = the opener vs the 3-bet.
  PreflopDecision? decision(int step) {
    final o = opener;
    if (o == null) return null;
    return switch (step) {
      0 => openerDecision(o, trn: trn),
      1 => responder == null
          ? null
          : responderDecision(responder!, o, trn: trn),
      _ => (responder == null || responderAction != '3-bet')
          ? null
          : openerVs3BetDecision(o, responder!, trn: trn),
    };
  }

  /// Does the preflop action CLOSE into a heads-up pot (flop can be dealt)?
  bool get closed =>
      responderAction == 'Call' ||
      (responderAction == '3-bet' && openerResponse == 'Call');

  /// The solved postflop scenario this trail maps to, or null.
  String? get scenarioKey => opener == null
      ? null
      : trailScenarioKey(
          opener: opener!,
          responder: responder,
          responderAction: responderAction,
          openerResponse: openerResponse,
          trn: trn,
        );
}

/// The representative trail for a solved scenario key (the inverse of
/// [trailScenarioKey], picking the bucket's representative opener — used to
/// sync the strip when a spot is opened directly).
PreflopTrail trailForScenario(String key) => switch (key) {
      'srp_late_v_bb' => const PreflopTrail(
          opener: 'BTN', responder: 'BB', responderAction: 'Call'),
      'srp_middle_v_bb' => const PreflopTrail(
          opener: 'CO', responder: 'BB', responderAction: 'Call'),
      'srp_early_v_bb' => const PreflopTrail(
          opener: 'UTG', responder: 'BB', responderAction: 'Call'),
      '3bp_bb_v_btn' => const PreflopTrail(
          opener: 'BTN',
          responder: 'BB',
          responderAction: '3-bet',
          openerResponse: 'Call'),
      _ => const PreflopTrail(),
    };

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
