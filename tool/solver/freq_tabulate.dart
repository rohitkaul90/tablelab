// GTO frequency library (DCE Q1) — Phase 1: the TABULATOR + schema.
//
// Consumes a solved TexasSolver dump tree (see SOLVER_PRIMER §6) and condenses it
// into library cells keyed by
//   {texture × spr-bucket × street × position × facing-node × hand-class}  →  {action: freq}
// the offline substrate the live `gtoFrequencyFact()` looks up (design:
// launch/GTO_FREQUENCY_LIBRARY.md). Operator-only; pure Dart over an already-saved
// dump (no solver invocation here — that's the phase-2 grid runner).
//
// HOW IT AGGREGATES (the load-bearing bit):
//  - Walk the tree. Each action_node belongs to one player (0 = OOP, 1 = IP,
//    universally — see primer §6). The node's per-combo strategy is that player's
//    GTO mix GIVEN they are at the node.
//  - We weight each combo by its REACH (probability it actually arrives here) =
//    the product of that player's own action frequencies down the line. Reach is
//    tracked per player: it changes only when that player acts, and a chance card
//    just removes conflicting combos. A combo that folds earlier drops to 0 reach
//    and stops contributing — the same numeric narrowing the solver does (primer §7).
//  - The acting player's combos are bucketed by `HandClass` (the SAME classifier
//    the live FACT + EQR use) on the running board, and reach-weighted action
//    frequencies accumulate per cell. Many turn/river cards that yield the same
//    TEXTURE merge into one cell (the texture re-bucketing the design calls for).
//
// Action labels are abstracted to a small stable vocabulary
//   {check, fold, call, bet_small, bet_big, raise, allin}  (+ bet / bet_mid)
// so the library never depends on exact chip sizes.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/decision_context.dart';
import 'package:tablelab/equity/texture_cell.dart';

import 'range_calib.dart' show parseComboKey;

// ── Schema ───────────────────────────────────────────────────────────────────

/// One library row: the GTO action mix for a hand class at a typed decision node.
class FreqCell {
  final String texture; // TextureCell.key
  final String sprBucket; // SprBucket.name (the spot's flop SPR regime)
  final String street; // flop | turn | river
  final String position; // oop | ip
  final String facing; // first_to_act | facing_check | facing_bet_small | …
  final String handClass; // HandClass.name

  /// Action label → frequency (0–1), summing to ~1 across the actions present.
  final Map<String, double> freqs;

  /// Reach mass behind this aggregate (Σ reach over the contributing combos,
  /// un-normalised). Low mass ⇒ thin/noisy cell → suppress at lookup time.
  final double reachWeight;

  FreqCell({
    required this.texture,
    required this.sprBucket,
    required this.street,
    required this.position,
    required this.facing,
    required this.handClass,
    required this.freqs,
    required this.reachWeight,
  });

  Map<String, dynamic> toJson() => {
        'texture': texture,
        'spr_bucket': sprBucket,
        'street': street,
        'position': position,
        'facing': facing,
        'hand_class': handClass,
        'freqs': {
          for (final e in freqs.entries) e.key: _round(e.value),
        },
        'reach_weight': _round(reachWeight),
      };

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;
}

/// A scenario's slice of the library (one preflop range pair).
class ScenarioLib {
  final String rangeIp;
  final String rangeOop;
  final Map<String, String> repFlops; // texture key → representative flop
  final List<FreqCell> cells;
  ScenarioLib(this.rangeIp, this.rangeOop, this.repFlops, this.cells);

  Map<String, dynamic> toJson() => {
        'range_ip': rangeIp,
        'range_oop': rangeOop,
        'rep_flops': repFlops,
        'cells': [for (final c in cells) c.toJson()],
      };
}

/// The full checked-in library file.
class FreqLibrary {
  final int version;
  final Map<String, dynamic> meta;
  final Map<String, ScenarioLib> scenarios;
  FreqLibrary({this.version = 1, required this.meta, required this.scenarios});

  Map<String, dynamic> toJson() => {
        'version': version,
        'meta': meta,
        'scenarios': {
          for (final e in scenarios.entries) e.key: e.value.toJson(),
        },
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

// ── Action-label abstraction ─────────────────────────────────────────────────

/// Map a node's raw action labels (e.g. ["CHECK","BET 6.6","BET 15","ALLIN"]) to
/// the stable library vocabulary, aligned 1:1 with the input list. BET actions
/// are ranked by chip size → bet_small / bet_big (/ bet_mid for any middle), or a
/// lone "bet" when the node offers a single bet size.
List<String> canonicalActionLabels(List<String> actions) {
  final betIdx = <int>[];
  final betAmt = <double>[];
  for (var i = 0; i < actions.length; i++) {
    if (actions[i].trim().toUpperCase().startsWith('BET')) {
      betIdx.add(i);
      betAmt.add(_amount(actions[i]));
    }
  }
  final betLabel = <int, String>{};
  if (betIdx.length == 1) {
    betLabel[betIdx[0]] = 'bet';
  } else if (betIdx.length > 1) {
    final order = List.generate(betIdx.length, (k) => k)
      ..sort((x, y) => betAmt[x].compareTo(betAmt[y]));
    for (var rank = 0; rank < order.length; rank++) {
      final idx = betIdx[order[rank]];
      betLabel[idx] = rank == 0
          ? 'bet_small'
          : (rank == order.length - 1 ? 'bet_big' : 'bet_mid');
    }
  }
  return [for (var i = 0; i < actions.length; i++) _label(actions[i], betLabel[i])];
}

String _label(String raw, String? betLbl) {
  final u = raw.trim().toUpperCase();
  if (u.startsWith('CHECK')) return 'check';
  if (u.startsWith('FOLD')) return 'fold';
  if (u.startsWith('CALL')) return 'call';
  if (u.startsWith('ALLIN') || u.startsWith('ALL_IN') || u.startsWith('ALL IN')) {
    return 'allin';
  }
  if (u.startsWith('RAISE')) return 'raise';
  if (u.startsWith('BET')) return betLbl ?? 'bet';
  return u.toLowerCase();
}

double _amount(String raw) {
  final m = RegExp(r'([0-9]+\.?[0-9]*)').firstMatch(raw);
  return m == null ? 0.0 : (double.tryParse(m.group(1)!) ?? 0.0);
}

// ── Tabulation ───────────────────────────────────────────────────────────────

String _streetName(int boardLen) =>
    boardLen <= 3 ? 'flop' : (boardLen == 4 ? 'turn' : 'river');

/// Canonical combo key from two card ints (order-independent).
String _ckey(List<int> cards) {
  final a = cards[0], b = cards[1];
  return a <= b ? '${a}_$b' : '${b}_$a';
}

/// Per-cell running accumulator.
class _CellAcc {
  final Map<String, double> weighted = {}; // action label → Σ reach·freq
  double totalReach = 0.0;
}

/// Tabulate one solved spot's dump [root] into library cells. [board] is the flop
/// (parsed ints); [sprBucket] is the spot's flop SPR regime (SprBucket.name).
/// [maxBoardLen] caps the depth walked (5 = river; pass 4 to stop at the turn for
/// tractability on huge dumps).
List<FreqCell> tabulateSpot(
  Map<String, dynamic> root, {
  required List<int> board,
  required String sprBucket,
  int maxBoardLen = 5,
}) {
  final acc = <String, _CellAcc>{};
  _walk(root, board, <int, Map<String, double>>{}, 'first_to_act', acc, sprBucket,
      maxBoardLen);

  final out = <FreqCell>[];
  acc.forEach((key, ca) {
    if (ca.totalReach <= 0) return;
    final parts = key.split('@@');
    final freqs = <String, double>{
      for (final e in ca.weighted.entries) e.key: e.value / ca.totalReach,
    };
    out.add(FreqCell(
      texture: parts[0],
      sprBucket: parts[1],
      street: parts[2],
      position: parts[3],
      facing: parts[4],
      handClass: parts[5],
      freqs: freqs,
      reachWeight: ca.totalReach,
    ));
  });
  return out;
}

void _walk(
  Map<String, dynamic> node,
  List<int> board,
  Map<int, Map<String, double>> reachByPlayer,
  String facing,
  Map<String, _CellAcc> acc,
  String sprBucket,
  int maxBoardLen,
) {
  final type = node['node_type'] as String?;
  final children = node['childrens'] as Map<String, dynamic>?;
  final strat = node['strategy'] as Map<String, dynamic>?;

  // Chance node: deal each child card, drop conflicting combos, recurse. Its
  // action children are the NEW street's OOP node → facing resets to first_to_act.
  if (type == 'chance_node' || (strat == null && children != null && type != 'action_node')) {
    if (children == null) return;
    if (board.length >= maxBoardLen) return;
    children.forEach((cardStr, child) {
      final card = parseCard(cardStr.trim());
      if (card < 0 || board.contains(card)) return;
      final nextBoard = [...board, card];
      final pruned = <int, Map<String, double>>{
        for (final e in reachByPlayer.entries)
          e.key: {
            for (final r in e.value.entries)
              if (!_keyHasCard(r.key, card)) r.key: r.value
          },
      };
      _walk(child as Map<String, dynamic>, nextBoard, pruned, 'first_to_act', acc,
          sprBucket, maxBoardLen);
    });
    return;
  }

  if (strat == null) return; // showdown / terminal leaf

  final actions = (strat['actions'] as List?)?.cast<String>() ?? const [];
  final byCombo = strat['strategy'] as Map<String, dynamic>?;
  if (actions.isEmpty || byCombo == null || byCombo.isEmpty) return;

  final player = node['player'] as int? ?? 0;
  final position = player == 0 ? 'oop' : 'ip';
  final canon = canonicalActionLabels(actions);

  // Initialise this player's reach map on first encounter: every combo present
  // at the player's first node arrives with full preflop weight (1.0 — our preset
  // ranges are unweighted). Thereafter absent ⇒ 0 (folded out), never resurrected.
  var reach = reachByPlayer[player];
  final firstNodeForPlayer = reach == null;
  if (reach == null) {
    reach = <String, double>{};
    byCombo.forEach((rawKey, _) {
      final cards = parseComboKey(rawKey);
      if (cards != null) reach![_ckey(cards)] = 1.0;
    });
  }

  // Tabulate: bucket combos by hand class, accumulate reach-weighted freqs.
  final tex = textureCell(board)?.key;
  if (tex != null) {
    final street = _streetName(board.length);
    byCombo.forEach((rawKey, vec) {
      if (vec is! List) return;
      final cards = parseComboKey(rawKey);
      if (cards == null) return;
      final w = firstNodeForPlayer ? 1.0 : (reach![_ckey(cards)] ?? 0.0);
      if (w <= 0) return;
      final hc = classifyHandClass(cards, board);
      if (hc == null) return;
      final cellKey =
          '$tex@@$sprBucket@@$street@@$position@@$facing@@${hc.name}';
      final ca = acc.putIfAbsent(cellKey, () => _CellAcc());
      for (var i = 0; i < canon.length && i < vec.length; i++) {
        final f = (vec[i] as num).toDouble();
        ca.weighted[canon[i]] = (ca.weighted[canon[i]] ?? 0.0) + w * f;
      }
      ca.totalReach += w;
    });
  }

  // Descend each action child: the acting player's reach is multiplied by that
  // action's per-combo frequency; the other player's reach is carried unchanged.
  if (children == null) return;
  final other = player == 0 ? 1 : 0;
  for (var ai = 0; ai < actions.length; ai++) {
    final childKey = children.keys.firstWhere(
      (k) =>
          k == actions[ai] ||
          k.toUpperCase().startsWith(actions[ai].trim().toUpperCase()),
      orElse: () => '',
    );
    if (childKey.isEmpty) continue;
    final child = children[childKey] as Map<String, dynamic>;

    final childReach = <String, double>{};
    byCombo.forEach((rawKey, vec) {
      if (vec is! List || ai >= vec.length) return;
      final cards = parseComboKey(rawKey);
      if (cards == null) return;
      final ck = _ckey(cards);
      final old = firstNodeForPlayer ? 1.0 : (reach![ck] ?? 0.0);
      final nr = old * (vec[ai] as num).toDouble();
      if (nr > 1e-9) childReach[ck] = nr;
    });

    final nextReach = <int, Map<String, double>>{
      player: childReach,
      if (reachByPlayer[other] != null) other: reachByPlayer[other]!,
    };
    _walk(child, board, nextReach, 'facing_${canon[ai]}', acc, sprBucket,
        maxBoardLen);
  }
}

/// Does a combo key "a_b" contain the given card int?
bool _keyHasCard(String ckey, int card) {
  final parts = ckey.split('_');
  return parts.length == 2 &&
      (int.tryParse(parts[0]) == card || int.tryParse(parts[1]) == card);
}

// ── Debug CLI ────────────────────────────────────────────────────────────────
//
// `dart run tool/solver/freq_tabulate.dart <dump.json> <flop e.g. Ks9h4c> <sprBucket>`
// prints the tabulated cells for one saved dump — eyeball a real solve in phase 2.

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('usage: freq_tabulate <dump.json> <flop e.g. Ks9h4c> '
        '<sprBucket: committed|shallow|medium|deep> [maxBoardLen]');
    exit(64);
  }
  final root = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final flop = <int>[];
  for (var i = 0; i + 1 < args[1].length; i += 2) {
    final c = parseCard(args[1].substring(i, i + 2));
    if (c >= 0) flop.add(c);
  }
  final maxLen = args.length > 3 ? int.tryParse(args[3]) ?? 5 : 5;
  final cells = tabulateSpot(root, board: flop, sprBucket: args[2], maxBoardLen: maxLen);
  cells.sort((a, b) => b.reachWeight.compareTo(a.reachWeight));
  stdout.writeln('${cells.length} cells (by reach mass):');
  for (final c in cells) {
    final mix = (c.freqs.entries.toList()
          ..sort((x, y) => y.value.compareTo(x.value)))
        .map((e) => '${e.key} ${(e.value * 100).toStringAsFixed(0)}%')
        .join('  ');
    stdout.writeln('  ${c.street} ${c.position} ${c.facing} ${c.handClass} '
        '[${c.texture}] (mass ${c.reachWeight.toStringAsFixed(1)}): $mix');
  }
}
