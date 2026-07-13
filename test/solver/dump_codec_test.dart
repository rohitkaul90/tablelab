// TLSD v1 codec tests: a hand-encoded byte fixture decoding to known
// structure, and tabulation equivalence against the SAME tree expressed as a
// JSON dump — the in-repo miniature of the WS1c dual-dump validation gate
// (tool/solver/validate_dump.dart runs the real-solve version). The streaming
// group locks the lazy cursor BYTE-IDENTICAL to the eager tree path.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';

import '../../tool/solver/dump_codec.dart';
import '../../tool/solver/freq_tabulate.dart';

List<int> _b(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

/// Minimal TLSD encoder — test-only, mirrors the C++ writer's format comment
/// (PCfrSolver.cpp) field by field.
class _Enc {
  final _bb = BytesBuilder();
  final _actionIds = <String, int>{};

  void u8(int v) => _bb.addByte(v & 0xFF);
  void u16(int v) {
    _bb.addByte(v & 0xFF);
    _bb.addByte((v >> 8) & 0xFF);
  }

  void u32(int v) {
    for (var i = 0; i < 4; i++) {
      _bb.addByte((v >> (8 * i)) & 0xFF);
    }
  }

  void f32(double v) {
    final d = ByteData(4)..setFloat32(0, v, Endian.little);
    _bb.add(d.buffer.asUint8List());
  }

  void str(String s) {
    u8(s.length);
    _bb.add(s.codeUnits);
  }

  void actionRef(String s) {
    final id = _actionIds[s];
    if (id != null) {
      u16(id);
      return;
    }
    u16(0xFFFF);
    str(s);
    _actionIds[s] = _actionIds.length;
  }

  void header({required List<int> board, int dumpRounds = 2}) {
    _bb.add('TLSD'.codeUnits);
    u8(1); // version
    u8(0); // flags
    u8(dumpRounds);
    u8(board.length);
    board.forEach(u8);
  }

  void dict(List<String> combos) {
    u32(combos.length);
    for (final key in combos) {
      final cards = [parseCard(key.substring(0, 2)), parseCard(key.substring(2))];
      u8(cards[0]);
      u8(cards[1]);
      str(key);
    }
  }

  void bitmap(List<bool> present) {
    final bytes = Uint8List((present.length + 7) >> 3);
    for (var i = 0; i < present.length; i++) {
      if (present[i]) bytes[i >> 3] |= 1 << (i & 7);
    }
    _bb.add(bytes);
  }

  void freqRow(List<double> freqs) {
    for (final f in freqs) {
      u16((f * 65535).round());
    }
  }

  Uint8List bytes() => _bb.toBytes();
}

/// Encode the SAME tree as freq_tabulate_test's `_dump()` JSON fixture:
/// flop Ks9h4c; OOP (player 0) root CHECK/BET 5/BET 15 → IP CHECK/BET 8 →
/// 2s turn → OOP CHECK/BET 10; every other line terminal. Optionally attach an
/// EV section at the root (decode-only — tabulation must ignore it).
Uint8List _fixture({bool withEv = false}) {
  final e = _Enc();
  e.header(board: _b('Ks 9h 4c'));
  e.dict(['QcQd', '7c2d']); // player 0 (OOP)
  e.dict(['AdAh']); // player 1 (IP)

  // Root: action, player 0.
  e.u8(0); // action node
  e.u8(0); // player
  e.u8(3); // nActions
  e.actionRef('CHECK');
  e.actionRef('BET 5');
  e.actionRef('BET 15');
  e.u8(withEv ? 3 : 1); // flags: strategy (+ev)
  e.bitmap([true, true]);
  e.freqRow([0.5, 0.3, 0.2]); // QcQd
  e.freqRow([0.8, 0.1, 0.1]); // 7c2d
  if (withEv) {
    e.bitmap([true, false]); // ev present for QcQd only
    e.u8(3);
    e.f32(1.5);
    e.f32(2.5);
    e.f32(-0.5);
  }

  // Child 1 of root: CHECK → IP action node.
  e.u8(0); // action node
  e.u8(1); // player
  e.u8(2);
  e.actionRef('CHECK'); // table reuse (id ref, not redefinition)
  e.actionRef('BET 8');
  e.u8(1);
  e.bitmap([true]);
  e.freqRow([0.7, 0.3]); // AdAh

  //   Child 1 of IP node: CHECK → chance node (turn 2s).
  e.u8(1); // chance node
  e.u16(1); // one card
  e.u8(parseCard('2s'));
  //     Turn OOP action node.
  e.u8(0);
  e.u8(0);
  e.u8(2);
  e.actionRef('CHECK');
  e.actionRef('BET 10');
  e.u8(1);
  e.bitmap([true, true]);
  e.freqRow([0.4, 0.6]); // QcQd
  e.freqRow([0.9, 0.1]); // 7c2d
  e.u8(2); // turn CHECK child: omitted
  e.u8(2); // turn BET 10 child: omitted

  //   Child 2 of IP node: BET 8 → omitted (terminal).
  e.u8(2);

  // Children 2+3 of root: BET 5 / BET 15 → omitted.
  e.u8(2);
  e.u8(2);
  return e.bytes();
}

/// The JSON twin (copied from freq_tabulate_test's `_dump()`).
Map<String, dynamic> _jsonDump() => {
      'node_type': 'action_node',
      'player': 0,
      'strategy': {
        'actions': ['CHECK', 'BET 5', 'BET 15'],
        'strategy': {
          'Qc Qd': [0.5, 0.3, 0.2],
          '7c 2d': [0.8, 0.1, 0.1],
        },
      },
      'childrens': {
        'CHECK': {
          'node_type': 'action_node',
          'player': 1,
          'strategy': {
            'actions': ['CHECK', 'BET 8'],
            'strategy': {
              'Ad Ah': [0.7, 0.3],
            },
          },
          'childrens': {
            'CHECK': {
              'node_type': 'chance_node',
              'dealcards': {
                '2s': {
                  'node_type': 'action_node',
                  'player': 0,
                  'strategy': {
                    'actions': ['CHECK', 'BET 10'],
                    'strategy': {
                      'Qc Qd': [0.4, 0.6],
                      '7c 2d': [0.9, 0.1],
                    },
                  },
                  'childrens': {
                    'CHECK': {'node_type': 'terminal_node'},
                    'BET 10': {'node_type': 'terminal_node'},
                  },
                },
              },
            },
            'BET 8': {'node_type': 'terminal_node'},
          },
        },
        'BET 5': {'node_type': 'terminal_node'},
        'BET 15': {'node_type': 'terminal_node'},
      },
    };

void main() {
  group('decodeTlsd', () {
    test('decodes the fixture structure', () {
      final dump = decodeTlsd(_fixture());
      expect(dump.version, 1);
      expect(dump.dumpRounds, 2);
      expect(dump.board, _b('Ks 9h 4c'));
      expect(dump.dicts[0].keys, ['QcQd', '7c2d']);
      expect(dump.dicts[0].cards[0], _b('Qc Qd'));
      expect(dump.dicts[1].keys, ['AdAh']);

      final root = dump.root!;
      expect(root.isChance, isFalse);
      expect(root.actions, ['CHECK', 'BET 5', 'BET 15']);
      expect(root.comboIdx, [0, 1]);
      // u16 round-trip of 0.5/0.3/0.2 within one quantum.
      expect(root.freqs[0] / 65535.0, closeTo(0.5, 1.5e-5));
      expect(root.freqs[5] / 65535.0, closeTo(0.1, 1.5e-5));

      final ip = root.children[0]!;
      // Action-string table reuse: "CHECK" referenced by id, decodes to text.
      expect(ip.actions, ['CHECK', 'BET 8']);
      expect(root.children[1], isNull); // omitted terminal
      expect(root.children[2], isNull);

      final chance = ip.children[0]!;
      expect(chance.isChance, isTrue);
      expect(chance.dealCards, [parseCard('2s')]);
      final turn = chance.dealChildren[0]!;
      expect(turn.actions, ['CHECK', 'BET 10']);
      expect(turn.children, [null, null]);
    });

    test('decodes an EV section without disturbing the tree', () {
      final dump = decodeTlsd(_fixture(withEv: true));
      final root = dump.root!;
      expect(root.ev, isNotNull);
      expect(root.ev!.keys, [0]); // QcQd only (bitmap [true, false])
      expect(root.ev![0], hasLength(3));
      expect(root.ev![0]![1], closeTo(2.5, 1e-6));
      expect(root.children[0], isNotNull); // tree after the EV section intact
    });

    test('rejects bad magic and truncated input', () {
      expect(() => decodeTlsd(Uint8List.fromList('JSON'.codeUnits)),
          throwsFormatException);
      final good = _fixture();
      expect(() => decodeTlsd(Uint8List.sublistView(good, 0, good.length - 3)),
          throwsA(anything));
    });
  });

  group('tabulateTlsd', () {
    test('matches tabulateSpot on the equivalent JSON dump', () {
      final jsonCells = tabulateSpot(_jsonDump(),
          board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);
      final tlsdCells = tabulateTlsd(decodeTlsd(_fixture()),
          board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);

      String key(FreqCell c) =>
          '${c.texture}|${c.sprBucket}|${c.street}|${c.position}|${c.facing}|${c.handClass}';
      final j = {for (final c in jsonCells) key(c): c};
      final t = {for (final c in tlsdCells) key(c): c};
      expect(t.keys.toSet(), j.keys.toSet());
      for (final k in j.keys) {
        final cj = j[k]!, ct = t[k]!;
        expect(ct.reachWeight, closeTo(cj.reachWeight, 1e-3),
            reason: 'reach for $k');
        for (final a in {...cj.freqs.keys, ...ct.freqs.keys}) {
          expect(ct.freqs[a] ?? 0.0, closeTo(cj.freqs[a] ?? 0.0, 1e-3),
              reason: 'freq $a for $k');
        }
      }
    });

    test('rejects a dump whose header board mismatches the spot flop', () {
      expect(
          () => tabulateTlsd(decodeTlsd(_fixture()),
              board: _b('As Kd 7h'), pot0: 10, effStack: 45),
          throwsStateError);
    });
  });

  group('tabulateDumpFile dispatch', () {
    test('routes a .tlsd file by magic bytes, not extension', () {
      final dir = Directory.systemTemp.createTempSync('tlsd_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Deliberately misleading extension: dispatch must ignore it.
      final path = '${dir.path}/dump.json';
      File(path).writeAsBytesSync(_fixture());
      expect(looksLikeTlsd(path), isTrue);
      final cells = tabulateDumpFile(path,
          board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);
      expect(cells, isNotEmpty);
    });
  });

  group('streaming tabulation', () {
    // The eager tree path is the in-process oracle: identical traversal order
    // and identical u16→double math mean the streaming cursor must produce
    // BYTE-IDENTICAL cell JSON, not merely within-tolerance.
    String eagerJson(Uint8List bytes,
            {List<int>? board, int maxBoardLen = 5}) =>
        jsonEncode([
          for (final c in tabulateTlsd(decodeTlsd(bytes),
              board: board ?? _b('Ks 9h 4c'),
              pot0: 10,
              effStack: 45,
              maxBoardLen: maxBoardLen))
            c.toJson()
        ]);
    String streamJson(Uint8List bytes,
        {List<int>? board, int maxBoardLen = 5}) {
      final dir = Directory.systemTemp.createTempSync('tlsd_stream_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/dump.bin';
      File(path).writeAsBytesSync(bytes);
      return jsonEncode([
        for (final c in tabulateTlsdStream(path,
            board: board ?? _b('Ks 9h 4c'),
            pot0: 10,
            effStack: 45,
            maxBoardLen: maxBoardLen))
          c.toJson()
      ]);
    }

    test('byte-identical to the eager path on the fixture', () {
      expect(streamJson(_fixture()), eagerJson(_fixture()));
    });

    test('byte-identical with an EV section (skipped structurally)', () {
      expect(streamJson(_fixture(withEv: true)),
          eagerJson(_fixture(withEv: true)));
    });

    test('byte-identical under maxBoardLen truncation (chance early-return '
        'leaves the turn subtree unconsumed — skip-to-sync realigns)', () {
      expect(streamJson(_fixture(), maxBoardLen: 3),
          eagerJson(_fixture(), maxBoardLen: 3));
    });

    test('skipped subtrees still intern action-table definitions', () {
      // A subtree the WALK never enters (child of a strategy-less action node
      // → isAction false → early return) DEFINES a new action string; a later
      // consumed sibling references it BY ID. The streaming cursor's
      // _skipNodeTree must intern while discarding, or the sibling's decode
      // throws 'action id not yet defined'.
      final e = _Enc();
      e.header(board: _b('Ks 9h 4c'));
      e.dict(['QcQd']); // player 0
      e.dict(['AdAh']); // player 1
      // Root: action p0, CHECK / BET 5.
      e.u8(0);
      e.u8(0);
      e.u8(2);
      e.actionRef('CHECK');
      e.actionRef('BET 5');
      e.u8(1); // strategy only
      e.bitmap([true]);
      e.freqRow([0.6, 0.4]);
      //   Child 0 (CHECK): p1 action node WITHOUT strategy (flags=0) — the
      //   walk visits it, sees isAction=false, returns; its child subtree is
      //   never consumed by the walk.
      e.u8(0);
      e.u8(1);
      e.u8(1);
      e.actionRef('CHECK'); // id ref
      e.u8(0); // flags: no strategy
      //     Its single child (inside the SKIPPED bytes): defines 'RAISE 42'.
      e.u8(0);
      e.u8(0);
      e.u8(2);
      e.actionRef('RAISE 42'); // ← DEFINITION inside skipped subtree
      e.actionRef('CHECK');
      e.u8(1);
      e.bitmap([true]);
      e.freqRow([1.0, 0.0]);
      e.u8(2); // omitted
      e.u8(2); // omitted
      //   Child 1 (BET 5): p1 action node whose action REFERENCES 'RAISE 42'
      //   by id (the encoder reuses the table entry).
      e.u8(0);
      e.u8(1);
      e.u8(1);
      e.actionRef('RAISE 42'); // ← ID REFERENCE, defined in skipped bytes
      e.u8(1);
      e.bitmap([true]);
      e.freqRow([1.0]);
      e.u8(2); // its child: omitted
      final bytes = e.bytes();

      // Sanity: the reference really is an id ref, not a redefinition.
      expect(String.fromCharCodes(bytes).indexOf('RAISE 42'),
          String.fromCharCodes(bytes).lastIndexOf('RAISE 42'));

      expect(streamJson(bytes), eagerJson(bytes));
    });

    test('finish() rejects trailing bytes after the root', () {
      final junk = Uint8List.fromList([..._fixture(), 0xDE, 0xAD]);
      final dir = Directory.systemTemp.createTempSync('tlsd_junk_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/dump.bin';
      File(path).writeAsBytesSync(junk);
      expect(
          () => tabulateTlsdStream(path,
              board: _b('Ks 9h 4c'), pot0: 10, effStack: 45),
          throwsFormatException);
    });

    test('truncated stream throws instead of returning partial cells', () {
      final good = _fixture();
      final dir = Directory.systemTemp.createTempSync('tlsd_trunc_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/dump.bin';
      File(path)
          .writeAsBytesSync(Uint8List.sublistView(good, 0, good.length - 3));
      expect(
          () => tabulateTlsdStream(path,
              board: _b('Ks 9h 4c'), pot0: 10, effStack: 45),
          throwsA(anything));
    });

    test('default tabulateDumpFile dispatch equals both TLSD paths', () {
      // The TLSOLVE_TABULATE_EAGER=1 hatch can't be exercised in-process
      // (Platform.environment is immutable) — it's covered by the real-dump
      // eager-vs-streaming diff in the rollout checklist.
      final dir = Directory.systemTemp.createTempSync('tlsd_disp_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/dump.bin';
      File(path).writeAsBytesSync(_fixture());
      final viaDispatch = jsonEncode([
        for (final c in tabulateDumpFile(path,
            board: _b('Ks 9h 4c'), pot0: 10, effStack: 45))
          c.toJson()
      ]);
      expect(viaDispatch, eagerJson(_fixture()));
    });
  });
}
