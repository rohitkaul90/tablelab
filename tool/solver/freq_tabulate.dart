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

import 'dump_codec.dart';

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

  // Backstop: never let a stray non-finite value (NaN/Infinity) reach the JSON
  // encoder — it throws and nukes the ENTIRE library write (losing a multi-hour
  // solve at the final step). The merge guards against the only known source
  // (zero-reach-mass groups), but coerce here too so one bad cell can't crash
  // the whole file.
  static double _round(double v) {
    if (!v.isFinite) return 0.0;
    return (v * 1000).roundToDouble() / 1000;
  }
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

/// Per-street SPR-tracking state, threaded down the walk. SPR is recomputed at
/// each street boundary (chance node) because the pot grows and stacks shrink as
/// chips go in — so a cell is bucketed by the SPR **at its own street**, matching
/// what the live `villain_range` path computes (effStack ÷ pot-at-street-start),
/// NOT the flop spot's regime. (Storing every cell under the flop regime made
/// turn cells mismatch the live shallower turn SPR → systematic lookup misses.)
///
/// PUBLIC (not `_SprState`): explorer_pack.dart walks the same dumps and reuses
/// this verified chip accounting (street "to"-totals, all-in amounts, pot
/// reconstruction) for its per-node pot/toCall/behind fields — one copy, no fork.
class SprState {
  /// Effective stack behind at the FLOP (constant for the whole spot).
  final double effStack;

  /// Pot at the start of the CURRENT street (before this street's betting).
  final double potStreetStart;

  /// Chips EACH player committed over PRIOR streets (equal for both, since any
  /// line that reaches a later street closed with matched contributions).
  final double committedPrior;

  /// Chips committed WITHIN the current street so far, per position ('oop'/'ip').
  final Map<String, double> streetContrib;

  /// Cached SprBucket.name for the current street (computed once at street entry).
  final String bucket;

  SprState({
    required this.effStack,
    required this.potStreetStart,
    required this.committedPrior,
    required this.streetContrib,
    required this.bucket,
  });

  /// SPR at the start of a street = remaining effective stack ÷ street-start pot.
  static String _bucketFor(double effStack, double committedPrior, double pot) =>
      pot <= 0 ? 'medium' : sprBucket((effStack - committedPrior) / pot).name;

  /// Root state for the flop: nothing committed yet, pot = the flop pot.
  factory SprState.flop(double pot0, double effStack) => SprState(
        effStack: effStack,
        potStreetStart: pot0,
        committedPrior: 0,
        streetContrib: const {'oop': 0, 'ip': 0},
        bucket: _bucketFor(effStack, 0, pot0),
      );

  /// Advance into the next street after a chance node. The just-closed street's
  /// matched contribution (each player's chips) = min of the two street contribs
  /// — equal on a properly-closed street (bet→call or check→check). The new pot
  /// folds in BOTH players' chips; committedPrior advances by the matched amount.
  SprState nextStreet() {
    final oop = streetContrib['oop'] ?? 0;
    final ip = streetContrib['ip'] ?? 0;
    final matched = oop < ip ? oop : ip;
    final newPot = potStreetStart + oop + ip;
    final newPrior = committedPrior + matched;
    return SprState(
      effStack: effStack,
      potStreetStart: newPot,
      committedPrior: newPrior,
      streetContrib: const {'oop': 0, 'ip': 0},
      bucket: _bucketFor(effStack, newPrior, newPot),
    );
  }

  /// State after [position] takes [rawAction] (updates that player's within-street
  /// "to"-total; TexasSolver action amounts are street totals, not increments).
  SprState afterAction(String position, String rawAction) {
    final other = position == 'oop' ? 'ip' : 'oop';
    final mine = streetContrib[position] ?? 0;
    final theirs = streetContrib[other] ?? 0;
    final u = rawAction.trim().toUpperCase();
    double to;
    if (u.startsWith('CHECK') || u.startsWith('FOLD')) {
      to = mine; // no chips added
    } else if (u.startsWith('CALL')) {
      to = theirs; // match the outstanding wager
    } else if (u.startsWith('ALLIN') ||
        u.startsWith('ALL_IN') ||
        u.startsWith('ALL IN')) {
      to = effStack - committedPrior; // shove everything remaining
    } else {
      // BET x / RAISE x — x is the street "to"-total (verified vs real dumps).
      final m = RegExp(r'([0-9]+\.?[0-9]*)').firstMatch(rawAction);
      final parsed = m == null ? null : double.tryParse(m.group(1)!);
      if (parsed == null) {
        // A sizeless BET/RAISE would silently zero this street's chips and
        // mis-bucket every downstream SPR — loud, not silent (it shouldn't
        // happen: TexasSolver always emits an amount).
        stderr.writeln('WARN freq_tabulate: unparseable bet/raise "$rawAction" '
            '— SPR reconstruction may be wrong for this line.');
      }
      to = parsed ?? mine;
    }
    return SprState(
      effStack: effStack,
      potStreetStart: potStreetStart,
      committedPrior: committedPrior,
      streetContrib: {position: to, other: theirs},
      bucket: bucket,
    );
  }
}

/// Tabulate one solved spot's dump [root] into library cells. [board] is the flop
/// (parsed ints). [pot0]/[effStack] are the spot's flop pot + effective stack —
/// the SPR bucket is re-derived per street from these as the pot grows (see
/// [SprState]). [maxBoardLen] caps the depth walked (5 = river; pass 4 to stop
/// at the turn for tractability on huge dumps).
/// Read a solver dump JSON file at [path] and tabulate it. The file-based entry
/// point so the WHOLE heavy step (read + jsonDecode + tree walk) can run in a
/// separate PROCESS (tool/solver/tabulate_one.dart) — the multi-GB String + Map
/// stay local to that process's own heap and are freed when it exits, off the
/// caller's heap/GC. Returns the same cells as [tabulateSpot] on the parsed root.
List<FreqCell> tabulateDumpFile(
  String path, {
  required List<int> board,
  required double pot0,
  required double effStack,
  int maxBoardLen = 5,
}) {
  // Dispatch on the file's magic bytes, not its extension: a TLSD binary dump
  // (dump_result_bin) is STREAMED — decoded node-by-node during the walk, never
  // materializing the tree (the eager typed-tree path remains available via
  // TLSOLVE_TABULATE_EAGER=1 as the field rollback; both produce BIT-IDENTICAL
  // cells — same traversal order, same u16 math — locked by tests). Anything
  // else is the legacy JSON path, kept intact as the validation oracle. The
  // env hatch lives HERE so it covers tabulate_one, validate_dump, and the
  // debug CLI in one place.
  if (looksLikeTlsd(path)) {
    if (Platform.environment['TLSOLVE_TABULATE_EAGER'] == '1') {
      return tabulateTlsd(readTlsdFile(path),
          board: board,
          pot0: pot0,
          effStack: effStack,
          maxBoardLen: maxBoardLen);
    }
    return tabulateTlsdStream(path,
        board: board, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
  }
  final root = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return tabulateSpot(root,
      board: board, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
}

/// Tabulate a TLSD dump via the STREAMING cursor: nodes decode on demand in
/// walk order and are discarded behind it, so retained heap is the raw bytes +
/// O(depth) — the fix for tabulation being the bulk fleet's throughput ceiling
/// (deep tabulates ran 20-40 min under saturation with the eager tree; see
/// BULK_DENSITY_RUNBOOK.md). Same board sanity check as [tabulateTlsd];
/// `finish()` restores the eager parser's trailing-bytes integrity check.
List<FreqCell> tabulateTlsdStream(
  String path, {
  required List<int> board,
  required double pot0,
  required double effStack,
  int maxBoardLen = 5,
}) {
  final dump = readTlsdStreamFile(path);
  if (dump.board.length >= 3 &&
      !(board.toSet().containsAll(dump.board.take(3)))) {
    throw StateError('TLSD board ${dump.board} does not match spot flop $board');
  }
  final root = dump.root;
  if (root == null) return const [];
  final cells = _tabulate(root,
      board: board, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
  dump.finish();
  return cells;
}

/// Tabulate a decoded TLSD dump. Sanity-checks the dump's own header board
/// against the caller's [board] — a flop mismatch means the grid wired the
/// wrong dump to the wrong spot (silent garbage otherwise).
List<FreqCell> tabulateTlsd(
  TlsdDump dump, {
  required List<int> board,
  required double pot0,
  required double effStack,
  int maxBoardLen = 5,
}) {
  if (dump.board.length >= 3 &&
      !(board.toSet().containsAll(dump.board.take(3)))) {
    throw StateError('TLSD board ${dump.board} does not match spot flop $board');
  }
  final root = dump.root;
  if (root == null) return const [];
  return _tabulate(TlsdNodeView(root, dump.dicts),
      board: board, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
}

List<FreqCell> tabulateSpot(
  Map<String, dynamic> root, {
  required List<int> board,
  required double pot0,
  required double effStack,
  int maxBoardLen = 5,
}) {
  return _tabulate(JsonNodeView(root),
      board: board, pot0: pot0, effStack: effStack, maxBoardLen: maxBoardLen);
}

List<FreqCell> _tabulate(
  DumpNodeView root, {
  required List<int> board,
  required double pot0,
  required double effStack,
  int maxBoardLen = 5,
}) {
  final acc = <String, _CellAcc>{};
  _walk(root, board, <String, Map<String, double>>{}, 'oop', 'first_to_act', acc,
      SprState.flop(pot0, effStack), maxBoardLen);

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
  DumpNodeView node,
  List<int> board,
  Map<String, Map<String, double>> reachByPos,
  String position, // 'oop' | 'ip' — derived STRUCTURALLY, not from the player id
  String facing,
  Map<String, _CellAcc> acc,
  SprState spr,
  int maxBoardLen,
) {
  // Chance node: deal each child card, drop conflicting combos, recurse. The new
  // street's first actor is OOP → position resets to 'oop', facing first_to_act.
  // (Format specifics — `dealcards` vs the synthetic-test `childrens` fallback,
  // TLSD typed nodes — live behind DumpNodeView in dump_codec.dart.)
  if (node.isChance) {
    if (board.length >= maxBoardLen) return;
    // The street just closed → fold this street's chips into the pot and
    // re-derive the SPR bucket for the new street (pot grew, stacks shrank).
    final nextSpr = spr.nextStreet();
    node.forEachDeal((card, child) {
      if (board.contains(card)) return;
      final nextBoard = [...board, card];
      final pruned = <String, Map<String, double>>{
        for (final e in reachByPos.entries)
          e.key: {
            for (final r in e.value.entries)
              if (!_keyHasCard(r.key, card)) r.key: r.value
          },
      };
      _walk(child, nextBoard, pruned, 'oop', 'first_to_act', acc, nextSpr,
          maxBoardLen);
    });
    return;
  }

  if (!node.isAction) return; // showdown / terminal leaf

  final actions = node.actions;
  final nCombos = node.comboCount;
  if (actions.isEmpty || nCombos == 0) return;

  // Position comes from tree STRUCTURE (root + post-chance = OOP, flipping each
  // action), NOT the dump's player field — that field's 0/1↔OOP/IP convention is
  // not reliable across solver builds (verified: a build had player 0 = IP).
  final canon = canonicalActionLabels(actions);

  // Initialise this position's reach map on first encounter: every combo present
  // at the player's first node arrives with full preflop weight (1.0 — our preset
  // ranges are unweighted). Thereafter absent ⇒ 0 (folded out), never resurrected.
  var reach = reachByPos[position];
  final firstNodeForPlayer = reach == null;
  if (reach == null) {
    reach = <String, double>{};
    for (var c = 0; c < nCombos; c++) {
      final cards = node.comboCards(c);
      if (cards != null) reach[_ckey(cards)] = 1.0;
    }
  }

  // Tabulate: bucket combos by hand class, accumulate reach-weighted freqs.
  final tex = textureCell(board)?.key;
  if (tex != null) {
    final street = _streetName(board.length);
    for (var c = 0; c < nCombos; c++) {
      if (!node.comboHasFreqs(c)) continue;
      final cards = node.comboCards(c);
      if (cards == null) continue;
      final w = firstNodeForPlayer ? 1.0 : (reach[_ckey(cards)] ?? 0.0);
      if (w <= 0) continue;
      final hc = classifyHandClass(cards, board);
      if (hc == null) continue;
      final cellKey =
          '$tex@@${spr.bucket}@@$street@@$position@@$facing@@${hc.name}';
      final ca = acc.putIfAbsent(cellKey, () => _CellAcc());
      final fl = node.freqLen(c);
      for (var i = 0; i < canon.length && i < fl; i++) {
        final f = node.freq(c, i);
        ca.weighted[canon[i]] = (ca.weighted[canon[i]] ?? 0.0) + w * f;
      }
      ca.totalReach += w;
    }
  }

  // Descend each action child: the acting player's reach is multiplied by that
  // action's per-combo frequency; the other player's reach is carried unchanged,
  // and the child node belongs to the OTHER position (strict alternation within a
  // street until it closes into a chance node).
  final other = position == 'oop' ? 'ip' : 'oop';
  for (var ai = 0; ai < actions.length; ai++) {
    final child = node.child(ai);
    if (child == null) continue;

    final childReach = <String, double>{};
    for (var c = 0; c < nCombos; c++) {
      if (!node.comboHasFreqs(c)) continue;
      final cards = node.comboCards(c);
      if (cards == null) continue;
      final ck = _ckey(cards);
      final old = firstNodeForPlayer ? 1.0 : (reach[ck] ?? 0.0);
      final nr = old * node.freq(c, ai);
      if (nr > 1e-9) childReach[ck] = nr;
    }

    final nextReach = <String, Map<String, double>>{
      position: childReach,
      if (reachByPos[other] != null) other: reachByPos[other]!,
    };
    // The FACING key the child inherits must use the live size buckets so the
    // live lookup (which keys facing on facing_bet_small/mid/big via the shared
    // betSizeBucket) can find the cell. canonicalActionLabels ranks bet sizes
    // RELATIVE to the node, so a single-size tree yields a bare 'bet' that no
    // live faced-bet key ever matches — bucket the faced bet by ABSOLUTE
    // pot-fraction instead. An ALL-IN likewise gets the live labels (an
    // opening shove is a bet, a shove over a wager is a raise — see
    // _facingActLabel); a bare 'facing_allin' would be unreachable (the live
    // _heroFacing never emits it). Non-bet actions keep their canonical label.
    final facingAct = _facingActLabel(canon[ai], actions[ai], position, spr);
    _walk(child, board, nextReach, other, 'facing_$facingAct', acc,
        spr.afterAction(position, actions[ai]), maxBoardLen);
  }
}

/// The live-lookup-compatible facing label for a taken action: bets bucket by
/// absolute pot-fraction; an all-in mirrors villain_range._heroFacing — with NO
/// prior aggression this street it's an opening BET (bucketed by fraction,
/// virtually always 'big'), over a wager it's a RAISE. Prior aggression this
/// street ⟺ either player already has street chips (a call can't exist without
/// a bet, and the same player can't bet twice consecutively), which the
/// SprState street contribs encode.
String _facingActLabel(
    String canonLabel, String rawAction, String actorPos, SprState spr) {
  if (canonLabel.startsWith('bet')) {
    return 'bet_${betSizeBucket(_betFrac(rawAction, actorPos, spr))}';
  }
  if (canonLabel == 'allin') {
    final other = actorPos == 'oop' ? 'ip' : 'oop';
    final mine = spr.streetContrib[actorPos] ?? 0;
    final theirs = spr.streetContrib[other] ?? 0;
    if (mine > 0 || theirs > 0) return 'raise';
    // Opening shove: to-total = everything behind; pot has no street chips yet.
    final to = spr.effStack - spr.committedPrior;
    final frac =
        spr.potStreetStart > 0 ? (to / spr.potStreetStart) : null;
    return 'bet_${betSizeBucket(frac)}';
  }
  return canonLabel;
}

/// The pot-fraction of a BET action: (its street "to"-total − the actor's chips
/// already in this street) ÷ the pot before the bet. Used to bucket a faced bet
/// into the shared small/mid/big labels. Null (→ 'mid') if the amount or pot is
/// unrecoverable. Matches the live `_betSizeFrac`/`betSizeBucket` pairing.
double? _betFrac(String rawAction, String actorPos, SprState spr) {
  final m = RegExp(r'([0-9]+\.?[0-9]*)').firstMatch(rawAction);
  final to = m == null ? null : double.tryParse(m.group(1)!);
  if (to == null) return null;
  final oop = spr.streetContrib['oop'] ?? 0;
  final ip = spr.streetContrib['ip'] ?? 0;
  final potBefore = spr.potStreetStart + oop + ip;
  if (potBefore <= 0) return null;
  final mine = spr.streetContrib[actorPos] ?? 0;
  return (to - mine) / potBefore;
}

/// Does a combo key "a_b" contain the given card int?
bool _keyHasCard(String ckey, int card) {
  final parts = ckey.split('_');
  return parts.length == 2 &&
      (int.tryParse(parts[0]) == card || int.tryParse(parts[1]) == card);
}

// ── Debug CLI ────────────────────────────────────────────────────────────────
//
// `dart run tool/solver/freq_tabulate.dart <dump.json> <flop e.g. Ks9h4c> <spr>`
// prints the tabulated cells for one saved dump — eyeball a real solve in phase 2.
// <spr> is the flop SPR (e.g. 6); the bucket is re-derived per street internally.
// [potScale] (default 10, the grid's pot) MUST match the pot the dump was solved
// at — the SPR reconstruction adds the dump's chip-scale bet amounts to it, so a
// wrong scale prints garbage buckets.

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('usage: freq_tabulate <dump.json> <flop e.g. Ks9h4c> '
        '<flopSpr e.g. 6> [maxBoardLen] [potScale=10]');
    exit(64);
  }
  final flop = <int>[];
  for (var i = 0; i + 1 < args[1].length; i += 2) {
    final c = parseCard(args[1].substring(i, i + 2));
    if (c >= 0) flop.add(c);
  }
  final spr = double.tryParse(args[2]);
  if (spr == null) {
    stderr.writeln('ERROR: <flopSpr> must be a number (e.g. 6), got "${args[2]}". '
        'The 3rd arg is the flop SPR now, not an sprBucket name.');
    exit(64);
  }
  final maxLen = args.length > 3 ? int.tryParse(args[3]) ?? 5 : 5;
  final pot0 = args.length > 4 ? double.tryParse(args[4]) ?? 10.0 : 10.0;
  // tabulateDumpFile dispatches on magic bytes — works for JSON and TLSD dumps.
  final cells = tabulateDumpFile(args[0],
      board: flop, pot0: pot0, effStack: spr * pot0, maxBoardLen: maxLen);
  cells.sort((a, b) => b.reachWeight.compareTo(a.reachWeight));
  stdout.writeln('${cells.length} cells (by reach mass):');
  for (final c in cells) {
    final mix = (c.freqs.entries.toList()
          ..sort((x, y) => y.value.compareTo(x.value)))
        .map((e) => '${e.key} ${(e.value * 100).toStringAsFixed(0)}%')
        .join('  ');
    stdout.writeln('  ${c.street} ${c.sprBucket} ${c.position} ${c.facing} '
        '${c.handClass} [${c.texture}] '
        '(mass ${c.reachWeight.toStringAsFixed(1)}): $mix');
  }
}
