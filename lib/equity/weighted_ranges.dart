// Weighted preflop ranges — the PokerCoaching-derived chart library.
//
// Parses assets/pc_ranges.json (built by tool/solver/ranges_pc/emit_app_asset.py
// from the normalized dataset; see tool/solver/RANGE_MIGRATION_PLAN.md). Unlike
// the legacy binary presets in gto_ranges.dart, every hand carries an action
// FREQUENCY mix ("KJs: call 46% / 3-bet 54%"), and raise actions carry their
// raise-TO size in bb.
//
// PURE Dart — no Flutter, no dart:io — so it runs in compute() isolates, under
// `dart run` for solver tooling/eval, and on web. The CALLER loads the JSON
// string (app: rootBundle, tools: File) and hands it to
// [PcRangeLibrary.fromJsonString]; this file never does I/O. Mirrors the
// gto_frequency_library.dart conventions.

import 'dart:convert';

/// Canonical action ids as emitted by the normalizer:
///   `f`          fold
///   `c`          call (or check where checking is legal)
///   `r:<to-bb>`  raise TO that many big blinds (e.g. `r:12`)
///   `a:<bb>`     all-in for that many bb (a raise to full effective stack)
///   `r`          raise with no size recorded (rare legacy label)
enum PcActionKind { fold, call, raise, allIn }

/// The single binarization policy for weighted→binary views: a hand is "in"
/// a binary range when it takes the relevant action at least this often.
/// Referenced by binaryHands, pcRfiHands, the equity presets, and the
/// quick-hand synthesis classifier — tune it HERE, nowhere else.
const double kPcActionThreshold = 0.5;

PcActionKind pcActionKind(String actionId) {
  switch (actionId.split(':').first) {
    case 'f':
      return PcActionKind.fold;
    case 'c':
      return PcActionKind.call;
    case 'a':
      return PcActionKind.allIn;
    default:
      return PcActionKind.raise;
  }
}

/// The raise-TO size in bb encoded in an action id, or null ('f', 'c', bare 'r').
double? pcActionSize(String actionId) {
  final i = actionId.indexOf(':');
  return i < 0 ? null : double.tryParse(actionId.substring(i + 1));
}

/// One normalized chart: a hero seat's full strategy at one preflop node.
class WeightedChart {
  final String id;
  final String game; // 'cash' | 'mtt'
  final String table; // '8max' | '6max' | 'hu'
  final num bbs;
  final double ante;
  final String hero; // PC seat: UTG, UTG1, LJ, HJ, CO, BTN, SB, BB
  final String node; // rfi | vs_open | vs_3bet | vs_4bet | vs_raise_call | ...
  final List<String> villains; // raiser first, then caller (vs_raise_call)
  final String sequence; // PC preflop line, e.g. 'F-F-F-F-F-R-F'
  final List<String> actions; // canonical action ids, aligned with hand rows
  /// hand → frequency per action (sums to ~1), or null = unreachable at this
  /// node (excluded by hero's own earlier action in the sequence).
  final Map<String, List<double>?> hands;

  const WeightedChart({
    required this.id,
    required this.game,
    required this.table,
    required this.bbs,
    required this.ante,
    required this.hero,
    required this.node,
    required this.villains,
    required this.sequence,
    required this.actions,
    required this.hands,
  });

  factory WeightedChart.fromJson(Map<String, dynamic> j) {
    final actions = (j['actions'] as List).cast<String>();
    final hands = <String, List<double>?>{};
    (j['hands'] as Map<String, dynamic>).forEach((hand, row) {
      hands[hand] = row == null
          ? null
          : (row as List).map((v) => (v as num).toDouble()).toList();
    });
    return WeightedChart(
      id: j['id'] as String,
      game: j['game'] as String,
      table: j['table'] as String,
      bbs: j['bbs'] as num,
      ante: (j['ante'] as num?)?.toDouble() ?? 0,
      hero: j['hero'] as String,
      node: j['node'] as String,
      villains: ((j['villains'] as List?) ?? const []).cast<String>(),
      sequence: (j['sequence'] as String?) ?? '',
      actions: actions,
      hands: hands,
    );
  }

  /// Total frequency of actions matching [pred] for [hand]; 0 for unreachable
  /// or unknown hands.
  double freqWhere(String hand, bool Function(String actionId) pred) {
    final row = hands[hand];
    if (row == null) return 0;
    var total = 0.0;
    for (var i = 0; i < actions.length; i++) {
      if (pred(actions[i])) total += row[i];
    }
    return total;
  }

  double foldFreq(String hand) =>
      freqWhere(hand, (a) => pcActionKind(a) == PcActionKind.fold);
  double callFreq(String hand) =>
      freqWhere(hand, (a) => pcActionKind(a) == PcActionKind.call);
  double raiseFreq(String hand) => freqWhere(
      hand,
      (a) =>
          pcActionKind(a) == PcActionKind.raise ||
          pcActionKind(a) == PcActionKind.allIn);

  /// Frequency of NOT folding (call + raise + all-in). Unreachable hands are 0.
  double continueFreq(String hand) =>
      freqWhere(hand, (a) => pcActionKind(a) != PcActionKind.fold);

  /// Binary view for consumers that need an in/out set (legacy preset shape):
  /// hands whose [pred]-frequency is at least [threshold].
  Set<String> binaryHands(
    double Function(String hand) freqOf, {
    double threshold = kPcActionThreshold,
  }) {
    final out = <String>{};
    for (final h in hands.keys) {
      if (freqOf(h) >= threshold) out.add(h);
    }
    return out;
  }

  /// Combo-weighted share (0–1) of all 1326 combos taking actions matching
  /// [pred]. Unreachable hands contribute 0.
  double comboShare(bool Function(String actionId) pred) {
    var total = 0.0;
    hands.forEach((hand, row) {
      if (row == null) return;
      var f = 0.0;
      for (var i = 0; i < actions.length; i++) {
        if (pred(actions[i])) f += row[i];
      }
      total += f * combosOfHand(hand);
    });
    return total / 1326;
  }
}

/// Number of concrete combos for a 169-grid hand label (pair 6, suited 4,
/// offsuit 12).
int combosOfHand(String hand) {
  if (hand.length == 2) return 6;
  return hand.endsWith('s') ? 4 : 12;
}

/// The loaded chart library with lookup indexing.
class PcRangeLibrary {
  final List<WeightedChart> charts;
  final Map<String, WeightedChart> _byId;
  final Map<String, List<WeightedChart>> _byNode;

  /// Charts dropped by the defensive parse (0 for a healthy asset).
  final int skippedCharts;

  PcRangeLibrary._(this.charts, this._byId, this._byNode, this.skippedCharts);

  /// Parses defensively: a malformed chart is SKIPPED, never allowed to take
  /// the other ~1,200 down with it (the codebase's parse-defensively doctrine;
  /// mirrors gto_frequency_library's tolerance). [skippedCharts] counts them
  /// so a broken regeneration is observable in tests.
  factory PcRangeLibrary.fromJson(Map<String, dynamic> j) {
    final charts = <WeightedChart>[];
    var skipped = 0;
    for (final raw in (j['charts'] as List? ?? const [])) {
      try {
        charts.add(WeightedChart.fromJson(raw as Map<String, dynamic>));
      } catch (_) {
        skipped++;
      }
    }
    final byId = <String, WeightedChart>{};
    final byNode = <String, List<WeightedChart>>{};
    for (final c in charts) {
      byId[c.id] = c;
      byNode.putIfAbsent(_nodeKey(c.game, c.table, c.hero, c.node), () => [])
          .add(c);
    }
    return PcRangeLibrary._(charts, byId, byNode, skipped);
  }

  /// Parse from a raw JSON string — suitable as a compute() payload.
  static PcRangeLibrary fromJsonString(String s) =>
      PcRangeLibrary.fromJson(jsonDecode(s) as Map<String, dynamic>);

  static String _nodeKey(String game, String table, String hero, String node) =>
      '$game|$table|$hero|$node';

  WeightedChart? byId(String id) => _byId[id];

  /// All depths available for a (game, table, hero, node) slice, ascending.
  List<num> depthsFor(String game, String table, String hero, String node) {
    final list = _byNode[_nodeKey(game, table, hero, node)] ?? const [];
    final bbs = list.map((c) => c.bbs).toSet().toList()..sort();
    return bbs;
  }

  /// Whether hero's only aggressive options in [c] are all-in (a proxy for
  /// "the raise hero is facing left no room" — i.e. hero faces a jam).
  static bool _allInOnlyAggression(WeightedChart c) {
    var hasRaise = false, hasAllIn = false;
    for (final a in c.actions) {
      final k = pcActionKind(a);
      if (k == PcActionKind.raise) hasRaise = true;
      if (k == PcActionKind.allIn) hasAllIn = true;
    }
    return hasAllIn && !hasRaise;
  }

  /// Find the chart for a node, snapping to the nearest available depth and
  /// (when [villains] is given) requiring a villain match. Returns null when
  /// the slice doesn't exist at all.
  ///
  /// [facingAllIn] disambiguates same-key sequence variants (the dataset holds
  /// e.g. BOTH "UTG facing a sized 3-bet" and "UTG facing a 3-bet jam" at the
  /// same game/table/bbs/hero/node/villains): true prefers the variant whose
  /// only aggressive response is all-in, false prefers the sized variant, and
  /// null defaults to the sized variant. Remaining ties break by action-count
  /// (richer chart first) then id — fully deterministic.
  WeightedChart? find({
    required String game,
    String table = '8max',
    required num bbs,
    required String hero,
    required String node,
    List<String>? villains,
    bool? facingAllIn,
  }) {
    var list = _byNode[_nodeKey(game, table, hero, node)];
    if (list == null || list.isEmpty) return null;
    if (villains != null) {
      final vMatch =
          list.where((c) => _sameVillains(c.villains, villains)).toList();
      if (vMatch.isEmpty) return null;
      list = vMatch;
    }
    // Nearest depth first (ties keep both for the preference pass below).
    num bestDist = double.infinity;
    for (final c in list) {
      final d = (c.bbs - bbs).abs();
      if (d < bestDist) bestDist = d;
    }
    final atDepth = list.where((c) => (c.bbs - bbs).abs() == bestDist).toList();
    final wantJam = facingAllIn ?? false;
    atDepth.sort((a, b) {
      // Deeper chart on an exact depth tie (90bb between 80 and 100 → 100).
      final byBbs = b.bbs.compareTo(a.bbs);
      if (byBbs != 0) return byBbs;
      final aJam = _allInOnlyAggression(a), bJam = _allInOnlyAggression(b);
      if (aJam != bJam) return (aJam == wantJam) ? -1 : 1;
      final byActions = b.actions.length.compareTo(a.actions.length);
      if (byActions != 0) return byActions;
      return a.id.compareTo(b.id);
    });
    return atDepth.first;
  }

  static bool _sameVillains(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
