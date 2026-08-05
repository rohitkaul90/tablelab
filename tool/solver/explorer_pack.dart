// GTO Explorer — per-spot "explorer pack" generator (design: launch/GTO_EXPLORER.md).
//
// Consumes a solved TexasSolver dump tree and emits an EXPLORER PACK: a manifest
// + street-chunked binary files holding, for EVERY action node, the acting
// player's per-combo strategy freqs, per-action EVs (our patched dump's `ev`),
// passive EV (`ev_passive`), reach, and equity vs the opponent's reach-weighted
// range. This is the data substrate for the in-app GTO Explorer (per-combo
// strategy grids / EV / equity charts) — the aggregate frequency library
// (freq_tabulate.dart) intentionally throws all of this away.
//
// Equity is NOT in the dump; it's computed here with lib/equity's evaluator:
//  - a one-time RANK CACHE ranks every registry combo on each (turn,river)
//    completion of the flop (~1176 boards × ~950 combos);
//  - flop nodes read a single oop×ip equity matrix accumulated over all
//    completions; turn nodes a per-turn-card matrix over its rivers (single-slot
//    cache); river nodes compute directly from the cached ranks. All three are
//    exact enumeration (no Monte Carlo), weighted per node by opponent reach.
//
// PACK LAYOUT (per spot):
//   <outDir>/manifest.json        version, format scales, spot meta, combo lists,
//                                 chunk index {id: {file, nodes, raw, gz}}
//   <outDir>/flop.bin.gz          all flop action nodes
//   <outDir>/turn/<card>.bin.gz   e.g. turn/Ah.bin.gz
//   <outDir>/river/<t><r>.bin.gz  e.g. river/Ah2c.bin.gz
// A node's chunk = its board state; its `path` is the full action path from the
// root with chance steps prefixed '@' (e.g. "CHECK/BET 6.6/CALL/@Ah/CHECK"), so
// one river chunk holds that runout's nodes across ALL betting lines.
//
// BINARY NODE RECORD (little-endian; scales recorded in the manifest `format`):
//   u16 pathLen + utf8 path
//   u8  street (0 flop / 1 turn / 2 river)     u8 actor (0 oop / 1 ip)
//   f32 potBefore   f32 toCall   f32 behind
//   u8  nActions; per action: u8 len + utf8 raw label ("BET 6.6")
//   u16 nCombos; per combo:
//     u16 comboId (index into the actor position's manifest combo list)
//     u16 reach (× 65535)
//     u8  equity (× 250; 255 = NA)
//     i16 evPassive (× 20 chips; -32768 = NA)
//     per action: u8 freq (× 250) + i16 ev (× 20 chips; -32768 = NA)
//
// The tree walk mirrors freq_tabulate._walk exactly: structural position
// derivation (root + post-chance = OOP, flipping per action — NOT node['player']),
// per-player reach maps (first node = 1.0, multiplied by action freqs, chance
// cards prune), dealcards-with-childrens-fallback chance detection. Chip
// accounting reuses the shared [SprState].

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/evaluator.dart';
import 'package:tablelab/explorer/pack_codec.dart';

import 'dump_codec.dart'
    show DumpNodeView, JsonNodeView;
import 'freq_tabulate.dart' show SprState;
import 'range_calib.dart' show parseComboKey;

// The FORMAT (constants + PackNode/PackCombo + decodeChunk) lives in the app
// (lib/explorer/pack_codec.dart — pure, web-safe) so generator and client
// share ONE definition; re-exported here so tooling/tests keep one import.
export 'package:tablelab/explorer/pack_codec.dart';

/// Combos below this reach are dropped from a node (they carry no strategy
/// mass worth rendering). Stats also count what a 0.5% ε would drop, to inform
/// harder pruning if pack sizes demand it. Generator-only (not format).
const double kReachEpsilon = 1e-4;

/// Equity is NA at nodes where the OPPONENT's total pruned reach mass is
/// below this floor (in combo-equivalents). On lines the opponent essentially
/// never takes, the weight vector is quantization dust and the weighted-mean
/// equity is numerically arbitrary — the real-dump pack oracle measured
/// 0.68-vs-0.10 "equities" at an opponent mass of 0.0006 across dump formats.
/// NA is the honest answer for the client too. Generator-only (not format).
const double kOppMassFloor = 0.05;

/// Generation counters + timings — the spike's measurement instrument.
class PackStats {
  int actionNodes = 0, chanceNodes = 0, terminalNodes = 0;
  int nodesWithEv = 0, nodesWithPassiveEv = 0;
  int combosEmitted = 0, combosDroppedLowReach = 0;
  int combosBelowHalfPct = 0; // emitted, but a 0.5% ε would drop them
  int chunkCount = 0;
  int rawBytes = 0, gzBytes = 0;
  int rankCacheMs = 0, matrixMs = 0, equityMs = 0, encodeMs = 0, writeMs = 0;

  double get evNodeCoverage =>
      actionNodes == 0 ? 0 : nodesWithEv / actionNodes;
  double get passiveEvNodeCoverage =>
      actionNodes == 0 ? 0 : nodesWithPassiveEv / actionNodes;
}

// ── Combo registry ───────────────────────────────────────────────────────────

/// Canonical combo key from two card ints (order-independent) — matches
/// freq_tabulate's reach-map keys.
String _ckey(List<int> cards) {
  final a = cards[0], b = cards[1];
  return a <= b ? '${a}_$b' : '${b}_$a';
}

class _ComboReg {
  final List<String> names = []; // 'AhKs' (higher card first)
  final List<List<int>> cards = [];
  final List<int> masks = []; // 52-bit card bitmasks
  final Map<String, int> byCkey = {};

  /// Registry size frozen when the rank cache is built; combos appended after
  /// that (defensive — shouldn't happen) get NA equity rather than a crash.
  int frozen = 0;

  int _add(List<int> c) {
    final hi = c[0] >= c[1] ? c[0] : c[1];
    final lo = identical(hi, c[0]) ? c[1] : c[0];
    names.add(cardName(hi) + cardName(lo));
    cards.add([hi, lo]);
    masks.add((1 << hi) | (1 << lo));
    final id = names.length - 1;
    byCkey[_ckey(c)] = id;
    return id;
  }

  /// Register a node's full combo set (first node per position — the fullest
  /// set), sorted by name for a deterministic manifest.
  void seed(Iterable<String> rawKeys) {
    seedCards([
      for (final k in rawKeys)
        if (parseComboKey(k) case final c?) c
    ]);
  }

  /// Card-pair form of [seed] (view/dict callers) — same dedupe + name sort.
  void seedCards(Iterable<List<int>> cardPairs) {
    final parsed = <List<int>>[];
    for (final c in cardPairs) {
      if (!byCkey.containsKey(_ckey(c))) parsed.add(c);
    }
    parsed.sort((x, y) {
      final hx = x[0] >= x[1] ? x[0] : x[1];
      final hy = y[0] >= y[1] ? y[0] : y[1];
      return (cardName(hx) + cardName(hx == x[0] ? x[1] : x[0]))
          .compareTo(cardName(hy) + cardName(hy == y[0] ? y[1] : y[0]));
    });
    parsed.forEach(_add);
  }

  int idOf(List<int> c) => byCkey[_ckey(c)] ?? _add(c);
}

// ── Equity: rank cache + matrices ────────────────────────────────────────────

class _Ranks {
  final Int32List oop; // -1 = combo collides with the runout
  final Int32List ip;
  _Ranks(this.oop, this.ip);
}

class _EqMatrix {
  final Float32List e; // nOop × nIp; -1 = blocked/never-valid pair
  final int nIp;
  _EqMatrix(this.e, this.nIp);
}

class _EquityEngine {
  final List<int> flop;
  final _ComboReg oop, ip;
  final PackStats stats;
  final List<int> _deck; // 49 cards off the flop

  Map<int, _Ranks>? _rankCache; // key = minCard*52 + maxCard
  _EqMatrix? _flopMat;
  int? _turnCard;
  _EqMatrix? _turnMat;

  _EquityEngine(this.flop, this.oop, this.ip, this.stats)
      : _deck = [
          for (var c = 0; c < 52; c++)
            if (!flop.contains(c)) c
        ];

  static int _key(int a, int b) => a < b ? a * 52 + b : b * 52 + a;

  /// Rank every registry combo on every (turn,river) completion — built once,
  /// lazily. ~1176 boards × (nOop + nIp) evaluate7 calls.
  Map<int, _Ranks> _ranks() {
    final cached = _rankCache;
    if (cached != null) return cached;
    final sw = Stopwatch()..start();
    oop.frozen = oop.names.length;
    ip.frozen = ip.names.length;
    final out = <int, _Ranks>{};
    final hand = List<int>.filled(7, 0);
    hand[0] = flop[0];
    hand[1] = flop[1];
    hand[2] = flop[2];
    for (var ti = 0; ti < _deck.length; ti++) {
      final t = _deck[ti];
      hand[3] = t;
      for (var ri = ti + 1; ri < _deck.length; ri++) {
        final r = _deck[ri];
        hand[4] = r;
        final extMask = (1 << t) | (1 << r);
        Int32List rankSide(_ComboReg reg) {
          final ranks = Int32List(reg.frozen);
          for (var i = 0; i < reg.frozen; i++) {
            if (reg.masks[i] & extMask != 0) {
              ranks[i] = -1;
              continue;
            }
            hand[5] = reg.cards[i][0];
            hand[6] = reg.cards[i][1];
            ranks[i] = evaluate7(hand);
          }
          return ranks;
        }

        out[_key(t, r)] = _Ranks(rankSide(oop), rankSide(ip));
      }
    }
    sw.stop();
    stats.rankCacheMs += sw.elapsedMilliseconds;
    _rankCache = out;
    return out;
  }

  /// Accumulate one runout's pairwise results into acc/cnt (oop rows × ip cols).
  static void _accumulate(_Ranks rk, int nA, int nB, List<int> aMasks,
      List<int> bMasks, Float64List acc, Int32List cnt) {
    for (var i = 0; i < nA; i++) {
      final ri = rk.oop[i];
      if (ri < 0) continue;
      final mi = aMasks[i];
      final base = i * nB;
      for (var j = 0; j < nB; j++) {
        final rj = rk.ip[j];
        if (rj < 0 || (mi & bMasks[j]) != 0) continue;
        acc[base + j] += ri > rj ? 1.0 : (ri == rj ? 0.5 : 0.0);
        cnt[base + j]++;
      }
    }
  }

  _EqMatrix _buildMatrix(Iterable<_Ranks> runouts) {
    final sw = Stopwatch()..start();
    final nA = oop.frozen, nB = ip.frozen;
    final acc = Float64List(nA * nB);
    final cnt = Int32List(nA * nB);
    for (final rk in runouts) {
      _accumulate(rk, nA, nB, oop.masks, ip.masks, acc, cnt);
    }
    final e = Float32List(nA * nB);
    for (var k = 0; k < e.length; k++) {
      e[k] = cnt[k] > 0 ? acc[k] / cnt[k] : -1.0;
    }
    sw.stop();
    stats.matrixMs += sw.elapsedMilliseconds;
    return _EqMatrix(e, nB);
  }

  _EqMatrix _flopMatrix() => _flopMat ??= _buildMatrix(_ranks().values);

  _EqMatrix _turnMatrix(int turnCard) {
    if (_turnCard == turnCard && _turnMat != null) return _turnMat!;
    final ranks = _ranks();
    _turnCard = turnCard;
    return _turnMat = _buildMatrix([
      for (final r in _deck)
        if (r != turnCard) ranks[_key(turnCard, r)]!
    ]);
  }

  /// Equity of the acting combo [actorId] vs the opponent's reach-weighted
  /// range at a node on [board]. -1 = NA (no valid opponent combo).
  double comboEquity(List<int> board, bool actorIsOop, int actorId,
      Float64List oppWeights) {
    final ranks = _ranks(); // also freezes the registries on first call
    final actorReg = actorIsOop ? oop : ip;
    if (actorId >= actorReg.frozen) return -1; // post-freeze defensive add
    if (board.length == 5) {
      // River: direct from cached ranks — no matrix.
      final rk = ranks[_key(board[3], board[4])];
      if (rk == null) return -1;
      final ra = actorIsOop ? rk.oop : rk.ip;
      final ro = actorIsOop ? rk.ip : rk.oop;
      final ri = ra[actorId];
      if (ri < 0) return -1;
      final mi = actorReg.masks[actorId];
      final oppReg = actorIsOop ? ip : oop;
      var num = 0.0, den = 0.0;
      final n = ro.length < oppWeights.length ? ro.length : oppWeights.length;
      for (var j = 0; j < n; j++) {
        final w = oppWeights[j];
        if (w <= 0) continue;
        final rj = ro[j];
        if (rj < 0 || (mi & oppReg.masks[j]) != 0) continue;
        num += w * (ri > rj ? 1.0 : (ri == rj ? 0.5 : 0.0));
        den += w;
      }
      return den > 0 ? num / den : -1;
    }
    final m = board.length == 3 ? _flopMatrix() : _turnMatrix(board[3]);
    var num = 0.0, den = 0.0;
    if (actorIsOop) {
      final base = actorId * m.nIp;
      final n = m.nIp < oppWeights.length ? m.nIp : oppWeights.length;
      for (var j = 0; j < n; j++) {
        final w = oppWeights[j];
        if (w <= 0) continue;
        final e = m.e[base + j];
        if (e < 0) continue;
        num += w * e;
        den += w;
      }
    } else {
      final nRows = oop.frozen;
      final n = nRows < oppWeights.length ? nRows : oppWeights.length;
      for (var j = 0; j < n; j++) {
        final w = oppWeights[j];
        if (w <= 0) continue;
        final e = m.e[j * m.nIp + actorId];
        if (e < 0) continue;
        num += w * (1.0 - e); // win+½tie is complement-symmetric
        den += w;
      }
    }
    return den > 0 ? num / den : -1;
  }
}

// ── Binary encoding ──────────────────────────────────────────────────────────

class _Bw {
  final BytesBuilder b = BytesBuilder();
  // Reused scratch buffers — these writers run in the per-combo × per-action
  // encode hot loop (~10^8 values on deep river dumps); a fresh list per
  // value was pure GC pressure. BytesBuilder.add() copies, so reuse is safe.
  final Uint8List _b2 = Uint8List(2);
  final Uint8List _b4 = Uint8List(4);
  late final ByteData _v2 = ByteData.sublistView(_b2);
  late final ByteData _v4 = ByteData.sublistView(_b4);

  void u8(int v) => b.addByte(v & 0xff);
  void u16(int v) {
    _v2.setUint16(0, v, Endian.little);
    b.add(_b2);
  }

  void i16(int v) {
    _v2.setInt16(0, v, Endian.little);
    b.add(_b2);
  }

  void u32(int v) {
    _v4.setUint32(0, v, Endian.little);
    b.add(_b4);
  }

  void f32(double v) {
    _v4.setFloat32(0, v, Endian.little);
    b.add(_b4);
  }

  void shortStr(String s) {
    final u = utf8.encode(s);
    u8(u.length);
    b.add(u);
  }

  void str16(String s) {
    final u = utf8.encode(s);
    u16(u.length);
    b.add(u);
  }
}

class _Chunk {
  final _Bw body = _Bw();
  int nodes = 0;
}

// ── Generation ───────────────────────────────────────────────────────────────

class _PackCtx {
  final Map<String, _Chunk> chunks = {};
  final _ComboReg oop = _ComboReg();
  final _ComboReg ip = _ComboReg();
  final PackStats stats = PackStats();
  late final _EquityEngine eq;
  final double effStack;
  final int maxBoardLen;
  _PackCtx(this.effStack, this.maxBoardLen);

  _Chunk chunkFor(List<int> board) {
    final id = board.length <= 3
        ? 'flop'
        : board.length == 4
            ? 'turn/${cardName(board[3])}'
            : 'river/${cardName(board[3])}${cardName(board[4])}';
    return chunks.putIfAbsent(id, () {
      stats.chunkCount++;
      return _Chunk();
    });
  }
}

int _quant(double v, int scale) {
  final q = (v * scale).round();
  return q < 0 ? 0 : (q > scale ? scale : q);
}

int _quantEv(double v) {
  final q = (v * kEvScale).round();
  return q < -32767 ? -32767 : (q > 32767 ? 32767 : q);
}

/// Generate an explorer pack from a parsed JSON dump [root] — thin wrapper
/// over [generatePackFromView] that keeps the original registry seeding
/// (OOP = root strategy keys; IP = first child-with-strategy in MAP order,
/// which the view's action-order iteration can't reproduce exactly). This is
/// the byte-oracle path for the TLSD port.
({Map<String, dynamic> manifest, PackStats stats}) generatePack(
  Map<String, dynamic> root, {
  required List<int> board,
  required double pot0,
  required double effStack,
  required String scenario,
  required String sprName,
  required String outDir,
  int maxBoardLen = 5,
}) {
  final rootStrat =
      (root['strategy'] as Map<String, dynamic>?)?['strategy'] as Map?;
  List<String>? ipKeys;
  final rootChildren = root['childrens'] as Map<String, dynamic>?;
  if (rootChildren != null) {
    for (final child in rootChildren.values) {
      final s = ((child as Map<String, dynamic>)['strategy']
          as Map<String, dynamic>?)?['strategy'] as Map?;
      if (s != null && s.isNotEmpty) {
        ipKeys = s.keys.cast<String>().toList();
        break;
      }
    }
  }
  return generatePackFromView(
    JsonNodeView(root),
    board: board,
    pot0: pot0,
    effStack: effStack,
    scenario: scenario,
    sprName: sprName,
    outDir: outDir,
    maxBoardLen: maxBoardLen,
    oopSeedKeys: rootStrat?.keys.cast<String>().toList(),
    ipSeedKeys: ipKeys,
  );
}

/// Generate an explorer pack from any [DumpNodeView] root (JSON or TLSD,
/// eager or streaming). Seeding: OOP from [oopSeedKeys] when given, else the
/// root node's own combos (identical for well-formed dumps — root IS OOP's
/// first node); IP from [ipSeedKeys] (REQUIRED for streaming TLSD, where
/// peeking at a child before the walk would violate the forward-only cursor
/// contract — pass the opponent player's dict keys from the TLSD header).
({Map<String, dynamic> manifest, PackStats stats}) generatePackFromView(
  DumpNodeView root, {
  required List<int> board,
  required double pot0,
  required double effStack,
  required String scenario,
  required String sprName,
  required String outDir,
  int maxBoardLen = 5,
  List<String>? oopSeedKeys,
  List<String>? ipSeedKeys,
}) {
  final ctx = _PackCtx(effStack, maxBoardLen);

  if (oopSeedKeys != null) {
    ctx.oop.seed(oopSeedKeys);
  } else {
    ctx.oop.seedCards([
      for (var i = 0; i < root.comboCount; i++)
        if (root.comboCards(i) case final c?) c
    ]);
  }
  if (ipSeedKeys != null) {
    ctx.ip.seed(ipSeedKeys);
  } else {
    // Eager-tree fallback (JSON view without explicit keys): peek the first
    // action child that has combos. NOT streaming-safe — streaming callers
    // must pass ipSeedKeys.
    for (var ai = 0; ai < root.actions.length; ai++) {
      final child = root.child(ai);
      if (child != null && child.isAction && child.comboCount > 0) {
        ctx.ip.seedCards([
          for (var i = 0; i < child.comboCount; i++)
            if (child.comboCards(i) case final c?) c
        ]);
        break;
      }
    }
  }
  ctx.eq = _EquityEngine(board, ctx.oop, ctx.ip, ctx.stats);

  _walkPack(root, board, <String, Map<String, double>>{}, 'oop', <String>[],
      SprState.flop(pot0, effStack), ctx);

  // Assemble + write files.
  final sw = Stopwatch()..start();
  Directory(outDir).createSync(recursive: true);
  final chunkIndex = <String, dynamic>{};
  ctx.chunks.forEach((id, chunk) {
    final header = _Bw()
      ..b.add(kPackMagic)
      ..u8(kPackVersion)
      ..u32(chunk.nodes);
    final raw = BytesBuilder(copy: false)
      ..add(header.b.takeBytes())
      ..add(chunk.body.b.takeBytes());
    final bytes = raw.takeBytes();
    final gz = gzip.encode(bytes);
    final file = '$id.bin.gz';
    final f = File('$outDir/$file');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(gz);
    ctx.stats.rawBytes += bytes.length;
    ctx.stats.gzBytes += gz.length;
    chunkIndex[id] = {
      'file': file,
      'nodes': chunk.nodes,
      'raw': bytes.length,
      'gz': gz.length,
    };
  });
  sw.stop();
  ctx.stats.writeMs += sw.elapsedMilliseconds;

  final manifest = <String, dynamic>{
    'version': kPackVersion,
    'format': {
      'freq_scale': kFreqScale,
      'equity_scale': kEquityScale,
      'reach_scale': kReachScale,
      'ev_scale': kEvScale,
      'ev_na': kEvNa,
      'equity_na': kEquityNa,
    },
    'scenario': scenario,
    'spr': sprName,
    'flop': [for (final c in board) cardName(c)].join(' '),
    'pot0': pot0,
    'eff_stack': effStack,
    'combos': {'oop': ctx.oop.names, 'ip': ctx.ip.names},
    'chunks': chunkIndex,
  };
  File('$outDir/manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(manifest));
  return (manifest: manifest, stats: ctx.stats);
}

void _walkPack(
  DumpNodeView node,
  List<int> board,
  Map<String, Map<String, double>> reachByPos,
  String position,
  List<String> path,
  SprState spr,
  _PackCtx ctx,
) {
  // Chance node — same detection + reach pruning as freq_tabulate._walk
  // (the view owns the detection; board-conflict filtering stays here).
  if (node.isChance) {
    ctx.stats.chanceNodes++;
    if (board.length >= ctx.maxBoardLen) return;
    final nextSpr = spr.nextStreet();
    node.forEachDeal((card, child) {
      if (board.contains(card)) return;
      final pruned = <String, Map<String, double>>{
        for (final e in reachByPos.entries)
          e.key: {
            for (final r in e.value.entries)
              if (!_ckeyHasCard(r.key, card)) r.key: r.value
          },
      };
      _walkPack(child, [...board, card], pruned, 'oop',
          [...path, '@${cardName(card)}'], nextSpr, ctx);
    });
    return;
  }

  if (!node.isAction) {
    ctx.stats.terminalNodes++;
    return;
  }

  final actions = node.actions;
  // Node combo index: ckey → view index, for combos with parseable cards AND
  // a usable freq vector — the exact membership the JSON path's `freqBy` had
  // (unparseable keys and non-List vectors excluded).
  final ckeyToIdx = <String, int>{};
  for (var i = 0; i < node.comboCount; i++) {
    if (!node.comboHasFreqs(i)) continue;
    final cards = node.comboCards(i);
    if (cards == null) continue;
    ckeyToIdx[_ckey(cards)] = i;
  }
  if (actions.isEmpty || ckeyToIdx.isEmpty) {
    ctx.stats.terminalNodes++;
    return;
  }
  ctx.stats.actionNodes++;

  final actorIsOop = position == 'oop';
  final actorReg = actorIsOop ? ctx.oop : ctx.ip;
  final oppReg = actorIsOop ? ctx.ip : ctx.oop;

  var reach = reachByPos[position];
  final firstNodeForPlayer = reach == null;
  reach ??= const <String, double>{};

  if (node.hasEv) ctx.stats.nodesWithEv++;
  if (node.hasEvPassive) ctx.stats.nodesWithPassiveEv++;

  // Opponent reach weights aligned to the opponent registry (for equity).
  final oppReach = reachByPos[actorIsOop ? 'ip' : 'oop'];
  final oppW = Float64List(oppReg.names.length);
  if (oppReach == null) {
    // Opponent hasn't acted yet → full range, weight 1 (collisions are
    // excluded by the rank/matrix layer).
    for (var j = 0; j < oppW.length; j++) {
      oppW[j] = 1.0;
    }
  } else {
    oppReach.forEach((ck, w) {
      final id = oppReg.byCkey[ck];
      if (id != null && id < oppW.length) oppW[id] = w;
    });
  }
  // Prune quantization-dust weights (same ε as the emit-side combo prune) and
  // NA-floor the node's equity when the opponent's surviving mass is
  // negligible — see kOppMassFloor. Keeps equity dump-format-stable AND
  // honest (a weighted mean over ~zero mass is noise, not information).
  var oppMass = 0.0;
  for (var j = 0; j < oppW.length; j++) {
    if (oppW[j] < kReachEpsilon) {
      oppW[j] = 0.0;
    } else {
      oppMass += oppW[j];
    }
  }
  final oppDead = oppMass < kOppMassFloor;

  // Temporary oracle diagnostics: TLPACK_DEBUG_PATH=<path> dumps the opponent
  // weight vector at that node to stderr (both generation paths).
  final dbgPath = Platform.environment['TLPACK_DEBUG_PATH'];
  if (dbgPath != null && path.join('/') == dbgPath) {
    var cnt = 0;
    var sum = 0.0;
    final first = <String>[];
    for (var j = 0; j < oppW.length; j++) {
      if (oppW[j] > 0) {
        cnt++;
        sum += oppW[j];
        if (first.length < 8) {
          first.add('${oppReg.names[j]}:${oppW[j].toStringAsFixed(6)}');
        }
      }
    }
    stderr.writeln('[dbg] "$dbgPath" actor=$position '
        'oppReachMap=${oppReach == null ? 'NULL(full-range)' : oppReach.length}'
        ' oppW nonzero=$cnt sum=${sum.toStringAsFixed(4)} first=$first');
  }

  // Chip state (from the shared verified SprState).
  final mine = spr.streetContrib[position] ?? 0;
  final theirs = spr.streetContrib[actorIsOop ? 'ip' : 'oop'] ?? 0;
  final potBefore = spr.potStreetStart +
      (spr.streetContrib['oop'] ?? 0) +
      (spr.streetContrib['ip'] ?? 0);
  final toCall = (theirs - mine) < 0 ? 0.0 : theirs - mine;
  final behind = ctx.effStack - spr.committedPrior - mine;

  // ── Emit the node record ──
  final swEnc = Stopwatch()..start();
  final chunk = ctx.chunkFor(board);
  final w = chunk.body;
  w.str16(path.join('/'));
  w.u8(board.length <= 3 ? 0 : (board.length == 4 ? 1 : 2));
  w.u8(actorIsOop ? 0 : 1);
  w.f32(potBefore);
  w.f32(toCall);
  w.f32(behind);
  w.u8(actions.length);
  for (final a in actions) {
    w.shortStr(a);
  }

  // Combos in registry order for determinism; drop reach < ε.
  final emit = <int>[];
  final emitIdx = <int>[]; // view index of each emitted combo
  final emitReach = <double>[];
  for (var id = 0; id < actorReg.names.length; id++) {
    final ck = _ckey(actorReg.cards[id]);
    final idx = ckeyToIdx[ck];
    if (idx == null) continue;
    final rw = firstNodeForPlayer ? 1.0 : (reach[ck] ?? 0.0);
    if (rw < kReachEpsilon) {
      ctx.stats.combosDroppedLowReach++;
      continue;
    }
    if (rw < 0.005) ctx.stats.combosBelowHalfPct++;
    emit.add(id);
    emitIdx.add(idx);
    emitReach.add(rw);
  }
  // Equity for the emitted combos, timed as one batch (a per-combo stopwatch
  // both undercounts sub-ms calls and adds real overhead). A dead-opponent
  // node skips the computation entirely — all NA.
  final eqVals = Float64List(emit.length);
  final swEq = Stopwatch()..start();
  for (var k = 0; k < emit.length; k++) {
    eqVals[k] =
        oppDead ? -1.0 : ctx.eq.comboEquity(board, actorIsOop, emit[k], oppW);
  }
  swEq.stop();
  ctx.stats.equityMs += swEq.elapsedMilliseconds;

  w.u16(emit.length);
  for (var k = 0; k < emit.length; k++) {
    final id = emit[k];
    final idx = emitIdx[k];
    final fLen = node.freqLen(idx);
    final ev = node.comboEv(idx);
    final pas = node.comboEvPassive(idx);
    w.u16(id);
    w.u16(_quant(emitReach[k], kReachScale));
    w.u8(eqVals[k] < 0 ? kEquityNa : _quant(eqVals[k], kEquityScale));
    w.i16(pas == null || pas.isEmpty ? kEvNa : _quantEv(pas.first));
    for (var a = 0; a < actions.length; a++) {
      w.u8(a < fLen ? _quant(node.freq(idx, a), kFreqScale) : 0);
      w.i16(ev != null && a < ev.length ? _quantEv(ev[a]) : kEvNa);
    }
    ctx.stats.combosEmitted++;
  }
  chunk.nodes++;
  swEnc.stop();
  // The equity batch ran inside the encode window — attribute it to equityMs
  // only (the two stats must partition the time, not double-count it).
  ctx.stats.encodeMs += swEnc.elapsedMilliseconds - swEq.elapsedMilliseconds;

  // ── Descend children (identical to freq_tabulate._walk) ──
  // child(ai) is requested in strictly increasing order BEFORE the parent's
  // frequencies are re-read for childReach — the streaming cursor's verified
  // access pattern (parent frame data stays readable while its child is open).
  final other = actorIsOop ? 'ip' : 'oop';
  for (var ai = 0; ai < actions.length; ai++) {
    final child = node.child(ai);
    if (child == null) continue;

    final childReach = <String, double>{};
    ckeyToIdx.forEach((ck, idx) {
      if (ai >= node.freqLen(idx)) return;
      final old = firstNodeForPlayer ? 1.0 : (reach![ck] ?? 0.0);
      final nr = old * node.freq(idx, ai);
      if (nr > 1e-9) childReach[ck] = nr;
    });

    final nextReach = <String, Map<String, double>>{
      position: childReach,
      if (reachByPos[other] != null) other: reachByPos[other]!,
    };
    _walkPack(child, board, nextReach, other, [...path, actions[ai]],
        spr.afterAction(position, actions[ai]), ctx);
  }
}

bool _ckeyHasCard(String ckey, int card) {
  final parts = ckey.split('_');
  return parts.length == 2 &&
      (int.tryParse(parts[0]) == card || int.tryParse(parts[1]) == card);
}

// ── Report + CLI ─────────────────────────────────────────────────────────────

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(2);

/// Human report of a generated pack — the spike's measurement output.
void printPackReport(Map<String, dynamic> manifest, PackStats s) {
  final chunks = manifest['chunks'] as Map<String, dynamic>;
  final byStreet = <String, ({int n, int raw, int gz, int nodes})>{};
  chunks.forEach((id, v) {
    final street = id == 'flop' ? 'flop' : id.split('/').first;
    final prev = byStreet[street] ?? (n: 0, raw: 0, gz: 0, nodes: 0);
    final m = v as Map<String, dynamic>;
    byStreet[street] = (
      n: prev.n + 1,
      raw: prev.raw + (m['raw'] as int),
      gz: prev.gz + (m['gz'] as int),
      nodes: prev.nodes + (m['nodes'] as int),
    );
  });
  stdout.writeln('── explorer pack: ${manifest['scenario']} '
      '${manifest['flop']} (${manifest['spr']}) ──');
  stdout.writeln('nodes: ${s.actionNodes} action / ${s.chanceNodes} chance / '
      '${s.terminalNodes} terminal');
  // Raw counts as well as % — a hero/flop-only EV patch reads as "0.0%" on a
  // 143k-node tree, which hides the real story (the Phase 0 spike hit this).
  stdout.writeln('EV coverage: ev ${s.nodesWithEv} nodes '
      '(${(s.evNodeCoverage * 100).toStringAsFixed(1)}%) · ev_passive '
      '${s.nodesWithPassiveEv} (${(s.passiveEvNodeCoverage * 100).toStringAsFixed(1)}%)');
  stdout.writeln('combos: ${s.combosEmitted} emitted · '
      '${s.combosDroppedLowReach} dropped (<$kReachEpsilon) · '
      '${s.combosBelowHalfPct} of emitted are <0.5% reach');
  for (final e in byStreet.entries) {
    stdout.writeln('  ${e.key.padRight(5)} ${e.value.n} chunk(s), '
        '${e.value.nodes} nodes, raw ${_mb(e.value.raw)} MB, '
        'gz ${_mb(e.value.gz)} MB');
  }
  stdout.writeln('total: raw ${_mb(s.rawBytes)} MB → gz ${_mb(s.gzBytes)} MB '
      '(${s.chunkCount} chunks)');
  final top = chunks.entries.toList()
    ..sort((a, b) => ((b.value as Map)['gz'] as int)
        .compareTo((a.value as Map)['gz'] as int));
  stdout.writeln('largest chunks: ${top.take(5).map((e) {
    final m = e.value as Map;
    return '${e.key} ${((m['gz'] as int) / 1024).toStringAsFixed(0)}K';
  }).join(', ')}');
  stdout.writeln('timings: rank-cache ${s.rankCacheMs}ms · matrices '
      '${s.matrixMs}ms · equity-rows ${s.equityMs}ms · encode ${s.encodeMs}ms '
      '· gzip+write ${s.writeMs}ms');
}

void main(List<String> args) {
  if (args.length < 5) {
    stderr.writeln('usage: explorer_pack <dump.json> <outDir> '
        '<flop e.g. Ks9h4c> <pot0> <effStack> [scenario] [sprName]');
    exit(64);
  }
  final flop = <int>[];
  for (var i = 0; i + 1 < args[2].length; i += 2) {
    final c = parseCard(args[2].substring(i, i + 2));
    if (c >= 0) flop.add(c);
  }
  final pot0 = double.tryParse(args[3]);
  final effStack = double.tryParse(args[4]);
  if (flop.length != 3 || pot0 == null || effStack == null) {
    stderr.writeln('explorer_pack: bad args');
    exit(64);
  }
  final sw = Stopwatch()..start();
  final root =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  stdout.writeln('parsed dump in ${sw.elapsedMilliseconds}ms');
  final r = generatePack(root,
      board: flop,
      pot0: pot0,
      effStack: effStack,
      scenario: args.length > 5 ? args[5] : 'srp_late_v_bb',
      sprName: args.length > 6 ? args[6] : '?',
      outDir: args[1]);
  printPackReport(r.manifest, r.stats);
}
