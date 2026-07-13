// TLSD v1 ("TableLab Solver Dump") — reader for the compact binary dump the
// patched TexasSolver emits via `dump_result_bin` (WS1 of the full-density
// cost plan; C++ writer lives in the licensed source, PCfrSolver.cpp).
//
// WHY: the JSON dump is ~15 GB at deep-river depth and jsonDecode needs a
// ~150 GB Dart heap — that single constraint capped the solve grid's
// `--parallel` at ~5 on a 1 TB box (measured ~16% core utilization). TLSD is
// ~7-15× smaller on disk and decodes into a compact TYPED tree (Uint16List
// freqs, int combo ids) that is ~25-50× lighter on the heap, so parse RAM
// stops being the binding constraint.
//
// FORMAT (all little-endian; must stay in lockstep with the C++ writer —
// see the format comment above `reConvertBinary` in PCfrSolver.cpp):
//   HEADER:
//     magic "TLSD" | u8 version=1 | u8 flags | u8 dumpRounds
//     u8 nBoard | nBoard × u8 cardInt
//     2 × player dictionary (player id 0,1):
//       u32 nCombos | per combo: u8 card1, u8 card2, u8 len, len bytes (the
//                     PrivateCards::toString() key the JSON dump uses)
//   NODE (recursive, pre-order):
//     u8 nodeType: 0=action | 1=chance | 2=omitted (terminal/showdown/pruned —
//                  exactly the nodes the JSON dump silently drops)
//     action: u8 player | u8 nActions | nActions × actionRef
//               (actionRef: u16 id, or 0xFFFF + u8 len + utf8 = define next id)
//             u8 nodeFlags (bit0 strategy, bit1 ev, bit2 evPassive)
//             [strategy]  bitmap ceil(n/8) LSB-first over the acting player's
//                         dictionary | per present combo: nActions × u16 freq
//             [ev]        bitmap | per present combo: u8 len | len × f32
//             [evPassive] bitmap | per present combo: u8 len | len × f32
//             nActions × NODE (children in action order)
//     chance: u16 nCards | per card: u8 cardInt (iso-remapped) | NODE
//
// CARD INTS: the solver's encoding ((rank-2)*4 + suit, suits c=0 d=1 h=2 s=3)
// is IDENTICAL to lib/equity/card.dart's (rank index 2→0 … A→12, same suit
// order) — verified against both sources — so ints pass through unconverted.
// The dictionary's combo STRING is still parsed as a cross-check at load.
//
// This file also defines [DumpNodeView] — the thin node abstraction that lets
// freq_tabulate's walk consume a JSON dump (Map tree) and a TLSD dump (typed
// tree) through one code path, so the JSON path survives as the validation
// oracle and the synthetic-fixture unit tests keep working.

import 'dart:io';
import 'dart:typed_data';

import 'package:tablelab/equity/card.dart';

import 'range_calib.dart' show parseComboKey;

// ── Typed dump model ─────────────────────────────────────────────────────────

/// One player's combo dictionary: parallel lists over dictionary index.
class TlsdDict {
  /// Dart card ints per combo, or null if the entry failed validation.
  final List<List<int>?> cards;

  /// The PrivateCards::toString() key (the JSON dump's map key).
  final List<String> keys;

  TlsdDict(this.cards, this.keys);

  int get length => keys.length;
}

/// A decoded TLSD tree node. Exactly one of the action/chance field groups is
/// populated; "omitted" nodes decode to null references, never to a TlsdNode.
class TlsdNode {
  // Action node fields.
  final int player; // solver player id 0/1 (informational — the walk derives
  // position structurally, same as the JSON path)
  final List<String> actions;

  /// Dictionary indices of the combos present at this node (bitmap order).
  final Int32List comboIdx;

  /// Row-major u16 freqs: present-combo row × action column, value/65535.
  final Uint16List freqs;

  /// Sparse per-combo EVs (dictionary index → per-action f32s). Only flop
  /// action nodes carry EVs today (the C++ EV patch's scope) — tiny maps.
  final Map<int, Float32List>? ev;
  final Map<int, Float32List>? evPassive;

  /// Children in action order; null = omitted (terminal/showdown/pruned).
  final List<TlsdNode?> children;

  // Chance node fields.
  final Int32List dealCards; // iso-remapped card ints
  final List<TlsdNode?> dealChildren;

  final bool isChance;

  TlsdNode.action({
    required this.player,
    required this.actions,
    required this.comboIdx,
    required this.freqs,
    required this.ev,
    required this.evPassive,
    required this.children,
  })  : isChance = false,
        dealCards = _emptyI32,
        dealChildren = const [];

  TlsdNode.chance({required this.dealCards, required this.dealChildren})
      : isChance = true,
        player = -1,
        actions = const [],
        comboIdx = _emptyI32,
        freqs = _emptyU16,
        ev = null,
        evPassive = null,
        children = const [];

  static final Int32List _emptyI32 = Int32List(0);
  static final Uint16List _emptyU16 = Uint16List(0);
}

/// A fully-decoded TLSD dump.
class TlsdDump {
  final int version;
  final int dumpRounds;
  final List<int> board; // the flop the spot was solved on (card ints)
  final List<TlsdDict> dicts; // [player0, player1]
  final TlsdNode? root; // null iff the root itself was omitted

  TlsdDump({
    required this.version,
    required this.dumpRounds,
    required this.board,
    required this.dicts,
    required this.root,
  });
}

/// The 4-byte magic. [looksLikeTlsd] lets callers dispatch a dump file to the
/// right parser without trusting file extensions.
const kTlsdMagic = [0x54, 0x4C, 0x53, 0x44]; // "TLSD"

bool looksLikeTlsd(String path) {
  final f = File(path).openSync();
  try {
    final head = f.readSync(4);
    if (head.length < 4) return false;
    for (var i = 0; i < 4; i++) {
      if (head[i] != kTlsdMagic[i]) return false;
    }
    return true;
  } finally {
    f.closeSync();
  }
}

// ── Reader ───────────────────────────────────────────────────────────────────

/// Decode a TLSD file. Reads the whole file into memory (raw bytes are the
/// compact part — ~1-2 GB at deep-river depth) and builds the typed tree.
TlsdDump readTlsdFile(String path) => decodeTlsd(File(path).readAsBytesSync());

TlsdDump decodeTlsd(Uint8List bytes) => _TlsdParser(bytes).parse();

/// Shared byte-level reader: primitives, the header/dict decode, and the
/// stateful interned action table. BOTH the eager parser and the streaming
/// cursor extend this, so the two decoders cannot drift on the format.
abstract class _TlsdReaderBase {
  final Uint8List _b;
  final ByteData _d;
  int _p = 0;
  final List<String> _actionTable = [];
  final List<int> _dictLens = [];

  _TlsdReaderBase(Uint8List bytes)
      : _b = bytes,
        _d = ByteData.sublistView(bytes);

  /// Magic + version + flags + dumpRounds + board + both player dicts.
  ({int version, int dumpRounds, List<int> board, List<TlsdDict> dicts})
      _header() {
    for (var i = 0; i < 4; i++) {
      if (_u8() != kTlsdMagic[i]) {
        throw const FormatException('TLSD: bad magic');
      }
    }
    final version = _u8();
    if (version != 1) throw FormatException('TLSD: unsupported version $version');
    _u8(); // flags (reserved)
    final dumpRounds = _u8();
    final nBoard = _u8();
    final board = [for (var i = 0; i < nBoard; i++) _u8()];
    final dicts = [_dict(), _dict()];
    return (
      version: version,
      dumpRounds: dumpRounds,
      board: board,
      dicts: dicts
    );
  }

  TlsdDict _dict() {
    final n = _u32();
    _dictLens.add(n);
    final cards = List<List<int>?>.filled(n, null);
    final keys = List<String>.filled(n, '');
    for (var i = 0; i < n; i++) {
      final c1 = _u8(), c2 = _u8();
      final key = _shortString();
      keys[i] = key;
      // Cross-check the raw ints against the string form; prefer the string
      // (the exact key the JSON oracle path uses) when they disagree.
      final parsed = parseComboKey(key);
      if (parsed != null) {
        cards[i] = parsed;
      } else if (c1 < 52 && c2 < 52 && c1 != c2) {
        cards[i] = [c1, c2];
      }
    }
    return TlsdDict(cards, keys);
  }

  int _dictLenFor(int player) {
    if (player < 0 || player >= _dictLens.length) {
      throw FormatException('TLSD: node player $player out of range');
    }
    return _dictLens[player];
  }

  /// Dictionary-index list of set bits in an LSB-first bitmap over [dictLen].
  Int32List _bitmap(int dictLen) {
    final nBytes = (dictLen + 7) >> 3;
    final start = _p;
    _skip(nBytes);
    var count = 0;
    for (var i = 0; i < dictLen; i++) {
      if (_b[start + (i >> 3)] & (1 << (i & 7)) != 0) count++;
    }
    final out = Int32List(count);
    var w = 0;
    for (var i = 0; i < dictLen; i++) {
      if (_b[start + (i >> 3)] & (1 << (i & 7)) != 0) out[w++] = i;
    }
    return out;
  }

  /// Skip a bitmap, returning only its set-bit count (no allocation). Trailing
  /// bits past [dictLen] in the final byte are masked off — the writer zeroes
  /// them, but a popcount over raw bytes must not trust that.
  int _bitmapCount(int dictLen) {
    final nBytes = (dictLen + 7) >> 3;
    final start = _p;
    _skip(nBytes);
    var count = 0;
    for (var i = 0; i < nBytes; i++) {
      var byte = _b[start + i];
      if (i == nBytes - 1 && (dictLen & 7) != 0) {
        byte &= (1 << (dictLen & 7)) - 1;
      }
      while (byte != 0) {
        count += byte & 1;
        byte >>= 1;
      }
    }
    return count;
  }

  String _actionRef() {
    final id = _u16();
    if (id != 0xFFFF) {
      if (id >= _actionTable.length) {
        throw FormatException('TLSD: action id $id not yet defined');
      }
      return _actionTable[id];
    }
    final s = _shortString();
    _actionTable.add(s);
    return s;
  }

  String _shortString() {
    final len = _u8();
    final s = String.fromCharCodes(_b, _p, _p + len);
    _skip(len);
    return s;
  }

  int _u8() {
    final v = _b[_p];
    _p += 1;
    return v;
  }

  int _u16() {
    final v = _d.getUint16(_p, Endian.little);
    _p += 2;
    return v;
  }

  int _u32() {
    final v = _d.getUint32(_p, Endian.little);
    _p += 4;
    return v;
  }

  double _f32() {
    final v = _d.getFloat32(_p, Endian.little);
    _p += 4;
    return v;
  }

  void _skip(int n) {
    _p += n;
    if (_p > _b.length) throw const FormatException('TLSD: truncated file');
  }
}

class _TlsdParser extends _TlsdReaderBase {
  _TlsdParser(super.bytes);

  TlsdDump parse() {
    final h = _header();
    final root = _node();
    if (_p != _b.length) {
      throw FormatException(
          'TLSD: ${_b.length - _p} trailing bytes after root node');
    }
    return TlsdDump(
      version: h.version,
      dumpRounds: h.dumpRounds,
      board: h.board,
      dicts: h.dicts,
      root: root,
    );
  }

  TlsdNode? _node() {
    final type = _u8();
    switch (type) {
      case 2: // omitted (terminal/showdown/depth-pruned)
        return null;
      case 0:
        return _actionNode();
      case 1:
        return _chanceNode();
      default:
        throw FormatException('TLSD: unknown node type $type at ${_p - 1}');
    }
  }

  TlsdNode _actionNode() {
    final player = _u8();
    final nActions = _u8();
    final actions = List<String>.generate(nActions, (_) => _actionRef());
    final flags = _u8();
    final dictLen = _dictLenFor(player);

    var comboIdx = TlsdNode._emptyI32;
    var freqs = TlsdNode._emptyU16;
    if (flags & 1 != 0) {
      final present = _bitmap(dictLen);
      comboIdx = present;
      freqs = Uint16List(present.length * nActions);
      var w = 0;
      for (var r = 0; r < present.length; r++) {
        for (var a = 0; a < nActions; a++) {
          freqs[w++] = _u16();
        }
      }
    }
    Map<int, Float32List>? ev, evPassive;
    if (flags & 2 != 0) ev = _evSection(dictLen);
    if (flags & 4 != 0) evPassive = _evSection(dictLen);

    final children =
        List<TlsdNode?>.generate(nActions, (_) => _node(), growable: false);
    return TlsdNode.action(
      player: player,
      actions: actions,
      comboIdx: comboIdx,
      freqs: freqs,
      ev: ev,
      evPassive: evPassive,
      children: children,
    );
  }

  TlsdNode _chanceNode() {
    final n = _u16();
    final cards = Int32List(n);
    final children = List<TlsdNode?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      cards[i] = _u8();
      children[i] = _node();
    }
    return TlsdNode.chance(dealCards: cards, dealChildren: children);
  }

  Map<int, Float32List> _evSection(int dictLen) {
    final present = _bitmap(dictLen);
    final out = <int, Float32List>{};
    for (final idx in present) {
      final len = _u8();
      final v = Float32List(len);
      for (var i = 0; i < len; i++) {
        v[i] = _f32();
      }
      out[idx] = v;
    }
    return out;
  }
}

// ── Walk abstraction ─────────────────────────────────────────────────────────

/// The minimal node surface freq_tabulate's walk needs, implemented over both
/// dump formats. Keep this SMALL — it exists so the walk has exactly one copy
/// (the JSON impl is the validation oracle for the TLSD impl).
abstract class DumpNodeView {
  bool get isChance;
  bool get isAction;

  /// Chance node: iterate dealt cards (Dart card ints) and their subtrees.
  /// Board-conflict filtering is the walker's job, not the view's.
  void forEachDeal(void Function(int card, DumpNodeView child) fn);

  /// Action node: raw action labels (e.g. "CHECK", "BET 6.6").
  List<String> get actions;

  /// Number of combos present at this node.
  int get comboCount;

  /// Dart card ints of combo [i], or null if unparseable (skipped by walkers).
  List<int>? comboCards(int i);

  /// Whether combo [i] carries a usable frequency vector (a malformed JSON row
  /// is "present" for reach initialisation but contributes no frequencies —
  /// mirrors the original walk's `vec is! List` guards).
  bool comboHasFreqs(int i);

  /// Frequency of action [actionIdx] for combo [comboIdx]; 0.0 out of range.
  double freq(int comboIdx, int actionIdx);

  /// Length of combo [comboIdx]'s frequency vector. The walk accumulates a
  /// 0.0 entry for an in-range zero but must NOT invent entries beyond a
  /// (malformed/short) JSON vector — the distinction keeps the JSON oracle
  /// path byte-identical to its pre-refactor output.
  int freqLen(int comboIdx);

  /// Child reached by taking action [actionIdx], or null if missing/terminal.
  DumpNodeView? child(int actionIdx);
}

/// View over the JSON dump's `Map<String, dynamic>` tree — byte-for-byte the
/// same semantics as the pre-refactor freq_tabulate walk (incl. the
/// `childrens`-as-dealcards fallback the synthetic unit-test dumps rely on and
/// the case/prefix-tolerant child key matching).
class JsonNodeView implements DumpNodeView {
  final Map<String, dynamic> node;

  JsonNodeView(this.node);

  Map<String, dynamic>? get _strat => node['strategy'] as Map<String, dynamic>?;

  Map<String, dynamic>? get _dealCards =>
      (node['dealcards'] ?? node['childrens']) as Map<String, dynamic>?;

  @override
  bool get isChance {
    final type = node['node_type'] as String?;
    return type == 'chance_node' ||
        (_strat == null && _dealCards != null && type != 'action_node');
  }

  @override
  bool get isAction => !isChance && _strat != null;

  @override
  void forEachDeal(void Function(int card, DumpNodeView child) fn) {
    _dealCards?.forEach((cardStr, child) {
      final card = parseCard(cardStr.trim());
      if (card < 0 || child is! Map<String, dynamic>) return;
      fn(card, JsonNodeView(child));
    });
  }

  @override
  List<String> get actions =>
      (_strat?['actions'] as List?)?.cast<String>() ?? const [];

  // Combo entries are materialized (and their keys parsed) once per node —
  // the original walk re-parsed every key up to 3× per node.
  List<MapEntry<String, dynamic>>? _entries;
  List<List<int>?>? _cards;

  List<MapEntry<String, dynamic>> get _combos {
    if (_entries != null) return _entries!;
    final byCombo = _strat?['strategy'] as Map<String, dynamic>?;
    _entries = byCombo == null
        ? const <MapEntry<String, dynamic>>[]
        : byCombo.entries.toList(growable: false);
    _cards = [for (final e in _entries!) parseComboKey(e.key)];
    return _entries!;
  }

  @override
  int get comboCount => _combos.length;

  @override
  List<int>? comboCards(int i) {
    _combos;
    return _cards![i];
  }

  @override
  bool comboHasFreqs(int i) => _combos[i].value is List;

  @override
  double freq(int comboIdx, int actionIdx) {
    final vec = _combos[comboIdx].value;
    if (vec is! List || actionIdx >= vec.length) return 0.0;
    // Hard cast, NOT a silent 0.0 coercion (review finding): the pre-refactor
    // walk did `(vec[i] as num).toDouble()`, so a corrupted strategy element
    // (null/string from a truncated dump) crashed the spot LOUDLY instead of
    // under-counting frequencies into the shipped library. Keep that.
    return (vec[actionIdx] as num).toDouble();
  }

  @override
  int freqLen(int comboIdx) {
    final vec = _combos[comboIdx].value;
    return vec is List ? vec.length : 0;
  }

  @override
  DumpNodeView? child(int actionIdx) {
    final children = node['childrens'] as Map<String, dynamic>?;
    if (children == null) return null;
    final acts = actions;
    if (actionIdx >= acts.length) return null;
    final want = acts[actionIdx];
    final key = children.keys.firstWhere(
      (k) => k == want || k.toUpperCase().startsWith(want.trim().toUpperCase()),
      orElse: () => '',
    );
    if (key.isEmpty) return null;
    final child = children[key];
    return child is Map<String, dynamic> ? JsonNodeView(child) : null;
  }
}

/// View over a decoded TLSD tree.
class TlsdNodeView implements DumpNodeView {
  final TlsdNode node;
  final List<TlsdDict> dicts;

  TlsdNodeView(this.node, this.dicts);

  @override
  bool get isChance => node.isChance;

  @override
  bool get isAction => !node.isChance && node.freqs.isNotEmpty;

  @override
  void forEachDeal(void Function(int card, DumpNodeView child) fn) {
    for (var i = 0; i < node.dealCards.length; i++) {
      final child = node.dealChildren[i];
      if (child == null) continue;
      fn(node.dealCards[i], TlsdNodeView(child, dicts));
    }
  }

  @override
  List<String> get actions => node.actions;

  TlsdDict get _dict => dicts[node.player];

  @override
  int get comboCount => node.comboIdx.length;

  @override
  List<int>? comboCards(int i) => _dict.cards[node.comboIdx[i]];

  @override
  bool comboHasFreqs(int i) => true;

  @override
  double freq(int comboIdx, int actionIdx) {
    if (actionIdx >= node.actions.length) return 0.0;
    return node.freqs[comboIdx * node.actions.length + actionIdx] / 65535.0;
  }

  @override
  int freqLen(int comboIdx) => node.actions.length;

  @override
  DumpNodeView? child(int actionIdx) {
    final c = node.children[actionIdx];
    return c == null ? null : TlsdNodeView(c, dicts);
  }
}

// ── Streaming reader (tabulate bottleneck fix) ───────────────────────────────
//
// The eager parser materializes the whole typed tree (tens of millions of
// nodes at deep-river depth) before the walk starts — that allocation/GC churn
// is what made tabulation the fleet's throughput ceiling. The streaming cursor
// exploits a structural fact: freq_tabulate's `_walk` visits nodes in EXACTLY
// the byte-stream's pre-order, requests action children in strictly increasing
// index order exactly once, and never revisits a node after its subtree
// completes. So nodes can be decoded ON DEMAND, retaining only the open
// root-to-current path (a frame stack), with unconsumed subtrees (the walk's
// early returns: maxBoardLen, board-conflict deals, terminal nodes)
// decode-DISCARDED via `_skipNodeTree` when the cursor needs to advance past
// them. Retained heap: the raw bytes + O(depth) frames, vs O(nodes).
//
// Identical traversal order + identical u16→double math ⇒ output cells are
// BIT-IDENTICAL to the eager path (locked by tests). The skip path MUST keep
// interning action-table definitions — the table is stateful across the whole
// stream, and a definition inside a skipped subtree can be referenced by id in
// a later sibling.

/// A lazily-decoded TLSD dump. [root] is valid until [finish] is called; the
/// walk must consume it strictly forward (freq_tabulate's `_walk` does).
class TlsdStreamDump {
  final int version;
  final int dumpRounds;
  final List<int> board;
  final List<TlsdDict> dicts;
  final DumpNodeView? root;
  final _TlsdStreamCursor _cursor;

  TlsdStreamDump._(
    this._cursor, {
    required this.version,
    required this.dumpRounds,
    required this.board,
    required this.dicts,
    required this.root,
  });

  /// Drain any unconsumed remainder and verify the stream ends exactly at the
  /// end of the buffer — the streaming equivalent of the eager parser's
  /// trailing-bytes check.
  void finish() => _cursor._finish();
}

TlsdStreamDump readTlsdStreamFile(String path) =>
    openTlsdStream(File(path).readAsBytesSync());

TlsdStreamDump openTlsdStream(Uint8List bytes) {
  final cursor = _TlsdStreamCursor(bytes);
  final h = cursor._header();
  cursor._streamDicts = h.dicts;
  final root = cursor._openRoot();
  return TlsdStreamDump._(
    cursor,
    version: h.version,
    dumpRounds: h.dumpRounds,
    board: h.board,
    dicts: h.dicts,
    root: root,
  );
}

/// One open node on the cursor's path stack. Node-local data stays readable
/// while the frame is on the stack (the walk re-reads the PARENT's strategy
/// after opening a child — verified access pattern).
class _StreamFrame {
  final bool isChance;
  // Action-node fields.
  final int player;
  final List<String> actions;
  final Int32List comboIdx;
  final int stratOff; // byte offset of the u16 freq block; -1 when absent
  // Chance-node fields.
  final int nDeals;

  /// Next unconsumed child index (action child or deal index).
  int nextChild = 0;

  _StreamFrame.action(this.player, this.actions, this.comboIdx, this.stratOff)
      : isChance = false,
        nDeals = 0;

  _StreamFrame.chance(this.nDeals)
      : isChance = true,
        player = -1,
        actions = const [],
        comboIdx = _emptyI32,
        stratOff = -1;

  static final Int32List _emptyI32 = Int32List(0);
}

class _TlsdStreamCursor extends _TlsdReaderBase {
  final List<_StreamFrame> _stack = [];
  List<TlsdDict> _streamDicts = const [];

  _TlsdStreamCursor(super.bytes);

  DumpNodeView? _openRoot() {
    final type = _u8();
    if (type == 2) return null;
    final f = _openFrame(type);
    _stack.add(f);
    return TlsdStreamNodeView._(this, f);
  }

  _StreamFrame _openFrame(int type) {
    switch (type) {
      case 0:
        final player = _u8();
        final nActions = _u8();
        final actions = List<String>.generate(nActions, (_) => _actionRef());
        final flags = _u8();
        final dictLen = _dictLenFor(player);
        var comboIdx = _StreamFrame._emptyI32;
        var stratOff = -1;
        if (flags & 1 != 0) {
          comboIdx = _bitmap(dictLen);
          stratOff = _p;
          _skip(comboIdx.length * nActions * 2);
        }
        if (flags & 2 != 0) _skipEvSection(dictLen);
        if (flags & 4 != 0) _skipEvSection(dictLen);
        return _StreamFrame.action(player, actions, comboIdx, stratOff);
      case 1:
        return _StreamFrame.chance(_u16());
      default:
        throw FormatException('TLSD: unknown node type $type at ${_p - 1}');
    }
  }

  /// Pop (and decode-discard the remainder of) every frame ABOVE [f]. After
  /// this, [f] is top-of-stack and `_p` sits at f's next unconsumed child.
  void _syncTo(_StreamFrame f) {
    while (_stack.isNotEmpty && !identical(_stack.last, f)) {
      _skipFrameRemainder(_stack.removeLast());
    }
    if (_stack.isEmpty) {
      throw StateError(
          'TLSD stream: frame not on the cursor path — the walk revisited a '
          'completed subtree (violates the streaming cursor contract)');
    }
  }

  void _skipFrameRemainder(_StreamFrame f) {
    if (f.isChance) {
      for (var i = f.nextChild; i < f.nDeals; i++) {
        _u8(); // dealt card
        _skipNodeTree();
      }
      f.nextChild = f.nDeals;
    } else {
      final n = f.actions.length;
      for (var i = f.nextChild; i < n; i++) {
        _skipNodeTree();
      }
      f.nextChild = n;
    }
  }

  DumpNodeView? _childOf(_StreamFrame f, int ai) {
    _syncTo(f);
    if (ai < f.nextChild) {
      throw StateError('TLSD stream: child($ai) requested after child '
          '${f.nextChild - 1} was consumed (non-increasing access)');
    }
    while (f.nextChild < ai) {
      _skipNodeTree();
      f.nextChild++;
    }
    f.nextChild++;
    final type = _u8();
    if (type == 2) return null; // omitted (terminal/showdown/pruned)
    final nf = _openFrame(type);
    _stack.add(nf);
    return TlsdStreamNodeView._(this, nf);
  }

  void _forEachDealOf(
      _StreamFrame f, void Function(int card, DumpNodeView child) fn) {
    while (f.nextChild < f.nDeals) {
      // Sync every iteration: the previous deal's subtree may be partially
      // consumed (board-conflict early return) or fully walked — either way
      // its frames may still be stacked above f.
      _syncTo(f);
      final card = _u8();
      f.nextChild++;
      final type = _u8();
      if (type == 2) continue; // omitted child: skip WITHOUT calling fn
      final nf = _openFrame(type);
      _stack.add(nf);
      fn(card, TlsdStreamNodeView._(this, nf));
    }
  }

  /// Decode-and-discard one whole node subtree. MUST intern action defs.
  void _skipNodeTree() {
    final type = _u8();
    switch (type) {
      case 2:
        return;
      case 0:
        final player = _u8();
        final nActions = _u8();
        for (var i = 0; i < nActions; i++) {
          _actionRef(); // interns new definitions — load-bearing
        }
        final flags = _u8();
        final dictLen = _dictLenFor(player);
        if (flags & 1 != 0) {
          final present = _bitmapCount(dictLen);
          _skip(present * nActions * 2);
        }
        if (flags & 2 != 0) _skipEvSection(dictLen);
        if (flags & 4 != 0) _skipEvSection(dictLen);
        for (var i = 0; i < nActions; i++) {
          _skipNodeTree();
        }
        return;
      case 1:
        final n = _u16();
        for (var i = 0; i < n; i++) {
          _u8(); // card
          _skipNodeTree();
        }
        return;
      default:
        throw FormatException('TLSD: unknown node type $type at ${_p - 1}');
    }
  }

  void _skipEvSection(int dictLen) {
    final present = _bitmapCount(dictLen);
    for (var i = 0; i < present; i++) {
      final len = _u8();
      _skip(len * 4);
    }
  }

  void _finish() {
    while (_stack.isNotEmpty) {
      _skipFrameRemainder(_stack.removeLast());
    }
    if (_p != _b.length) {
      throw FormatException(
          'TLSD: ${_b.length - _p} trailing bytes after root node');
    }
  }

  double _freqAt(int stratOff, int row, int nActions, int actionIdx) =>
      _d.getUint16(stratOff + (row * nActions + actionIdx) * 2, Endian.little) /
      65535.0;
}

/// Streaming [DumpNodeView]: same semantics as [TlsdNodeView], decoded lazily.
class TlsdStreamNodeView implements DumpNodeView {
  final _TlsdStreamCursor _cursor;
  final _StreamFrame _frame;

  TlsdStreamNodeView._(this._cursor, this._frame);

  @override
  bool get isChance => _frame.isChance;

  // Matches the eager `freqs.isNotEmpty`: strategy flag set AND ≥1 present
  // combo AND ≥1 action (stratOff is -1 unless flags&1 was set).
  @override
  bool get isAction =>
      !_frame.isChance &&
      _frame.stratOff >= 0 &&
      _frame.comboIdx.isNotEmpty &&
      _frame.actions.isNotEmpty;

  @override
  void forEachDeal(void Function(int card, DumpNodeView child) fn) =>
      _cursor._forEachDealOf(_frame, fn);

  @override
  List<String> get actions => _frame.actions;

  TlsdDict get _dict => _cursor._streamDicts[_frame.player];

  @override
  int get comboCount => _frame.comboIdx.length;

  @override
  List<int>? comboCards(int i) => _dict.cards[_frame.comboIdx[i]];

  @override
  bool comboHasFreqs(int i) => true;

  @override
  double freq(int comboIdx, int actionIdx) {
    if (actionIdx >= _frame.actions.length || _frame.stratOff < 0) return 0.0;
    return _cursor._freqAt(
        _frame.stratOff, comboIdx, _frame.actions.length, actionIdx);
  }

  @override
  int freqLen(int comboIdx) => _frame.actions.length;

  @override
  DumpNodeView? child(int actionIdx) => _cursor._childOf(_frame, actionIdx);
}
