// TLSD v1 codec tests: a hand-encoded byte fixture decoding to known
// structure, and tabulation equivalence against the SAME tree expressed as a
// JSON dump — the in-repo miniature of the WS1c dual-dump validation gate
// (tool/solver/validate_dump.dart runs the real-solve version).

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
}
