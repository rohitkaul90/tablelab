// GTO Explorer — pure aggregation of a node's per-combo data into the 13×13
// strategy-grid cells and the node-level action summary. No Flutter imports —
// unit-tested directly (test/explorer/grid_aggregation_test.dart).

import 'package:tablelab/equity/card.dart';

import 'pack_codec.dart';

/// One 13×13 cell's aggregate (e.g. all live AKs combos).
class GridCellAgg {
  final String hand; // 'AKs' / 'QQ' / 'T9o'
  final int comboCount; // combos present in the node
  final int maxCombos; // 6 pair / 4 suited / 12 offsuit
  final double reach; // Σ combo reach (0..maxCombos)
  final List<double> freqs; // reach-weighted mean per node action
  final double? equity; // reach-weighted mean, null if all NA
  GridCellAgg({
    required this.hand,
    required this.comboCount,
    required this.maxCombos,
    required this.reach,
    required this.freqs,
    required this.equity,
  });

  /// How "present" the cell is: reach mass ÷ the cell's full combo count.
  double get presence =>
      maxCombos == 0 ? 0 : (reach / maxCombos).clamp(0.0, 1.0);
}

/// Node-level summary for the overview panel.
class NodeSummary {
  final double totalReach; // Σ reach over combos ("combos" stat)
  final List<ActionAgg> actions; // aligned to node.actions
  final double? equityMean; // reach-weighted, null if no equity data
  NodeSummary(this.totalReach, this.actions, this.equityMean);
}

class ActionAgg {
  final String label; // raw solver label, 'BET 6.6'
  final double freq; // reach-weighted range frequency (0..1)
  final double combos; // Σ reach·freq — combos taking this action
  final double? evMean; // reach·freq-weighted EV (chips), null if absent
  ActionAgg(this.label, this.freq, this.combos, this.evMean);
}

/// Combo name ('AhKs', higher card first) → matrix cell, or null if unparseable.
(int, int)? comboCell(String name) {
  if (name.length != 4) return null;
  final hi = parseCard(name.substring(0, 2));
  final lo = parseCard(name.substring(2, 4));
  if (hi < 0 || lo < 0) return null;
  final rHi = cardRank(hi), rLo = cardRank(lo);
  final String hand;
  if (rHi == rLo) {
    hand = kRankChars[rHi] * 2;
  } else {
    final suited = cardSuit(hi) == cardSuit(lo);
    hand = '${kRankChars[rHi]}${kRankChars[rLo]}${suited ? 's' : 'o'}';
  }
  return handToCell(hand);
}

/// Aggregate [node]'s combos into a 13×13 grid. [comboNames] is the acting
/// position's manifest combo list (comboId → name). Cells with no live combo
/// are null.
List<List<GridCellAgg?>> aggregateGrid(PackNode node, List<String> comboNames) {
  final nActions = node.actions.length;
  final reach = List.generate(13, (_) => List.filled(13, 0.0));
  final count = List.generate(13, (_) => List.filled(13, 0));
  final wFreq = List.generate(13, (_) => List.filled(13 * nActions, 0.0));
  final wEq = List.generate(13, (_) => List.filled(13, 0.0));
  final wEqDen = List.generate(13, (_) => List.filled(13, 0.0));

  for (final c in node.combos) {
    if (c.comboId >= comboNames.length) continue;
    final cell = comboCell(comboNames[c.comboId]);
    if (cell == null) continue;
    final (row, col) = cell;
    reach[row][col] += c.reach;
    count[row][col]++;
    for (var a = 0; a < nActions && a < c.freqs.length; a++) {
      wFreq[row][col * nActions + a] += c.reach * c.freqs[a];
    }
    if (c.equity != null) {
      wEq[row][col] += c.reach * c.equity!;
      wEqDen[row][col] += c.reach;
    }
  }

  return List.generate(13, (row) {
    return List.generate(13, (col) {
      if (count[row][col] == 0) return null;
      final r = reach[row][col];
      return GridCellAgg(
        hand: cellToHand(row, col),
        comboCount: count[row][col],
        maxCombos: cellComboCount(row, col),
        reach: r,
        freqs: [
          for (var a = 0; a < nActions; a++)
            r > 0 ? wFreq[row][col * nActions + a] / r : 0.0,
        ],
        equity: wEqDen[row][col] > 0 ? wEq[row][col] / wEqDen[row][col] : null,
      );
    });
  });
}

/// Node-level action mix + stats for the overview panel.
NodeSummary summarizeNode(PackNode node) {
  final nActions = node.actions.length;
  var totalReach = 0.0;
  final wFreq = List.filled(nActions, 0.0);
  final wEv = List.filled(nActions, 0.0);
  final wEvDen = List.filled(nActions, 0.0);
  var wEq = 0.0, wEqDen = 0.0;
  for (final c in node.combos) {
    totalReach += c.reach;
    for (var a = 0; a < nActions && a < c.freqs.length; a++) {
      final w = c.reach * c.freqs[a];
      wFreq[a] += w;
      final ev = a < c.evs.length ? c.evs[a] : null;
      if (ev != null) {
        wEv[a] += w * ev;
        wEvDen[a] += w;
      }
    }
    if (c.equity != null) {
      wEq += c.reach * c.equity!;
      wEqDen += c.reach;
    }
  }
  return NodeSummary(
    totalReach,
    [
      for (var a = 0; a < nActions; a++)
        ActionAgg(
          node.actions[a],
          totalReach > 0 ? wFreq[a] / totalReach : 0.0,
          wFreq[a],
          wEvDen[a] > 0 ? wEv[a] / wEvDen[a] : null,
        ),
    ],
    wEqDen > 0 ? wEq / wEqDen : null,
  );
}
