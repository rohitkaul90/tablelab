// GTO Explorer — pack chunk CODEC (decode side) + format constants.
//
// PURE Dart (dart:convert + dart:typed_data only — no dart:io, no Flutter), so
// it runs in the app on every platform incl. web, inside compute() isolates,
// and under plain `dart run` for the offline tooling. The ENCODER lives with
// the pack generator (tool/solver/explorer_pack.dart), which re-exports this
// file so generator + app decode one format from one definition.
//
// BINARY NODE RECORD (little-endian; scales mirrored into the pack manifest):
//   u16 pathLen + utf8 path        (chance steps prefixed '@', e.g.
//                                   "CHECK/BET 6.6/CALL/@Ah/CHECK")
//   u8  street (0 flop / 1 turn / 2 river)     u8 actor (0 oop / 1 ip)
//   f32 potBefore   f32 toCall   f32 behind
//   u8  nActions; per action: u8 len + utf8 raw label ("BET 6.6")
//   u16 nCombos; per combo:
//     u16 comboId (index into the actor position's manifest combo list)
//     u16 reach (× 65535)
//     u8  equity (× 250; 255 = NA)
//     i16 evPassive (× 20 chips; -32768 = NA)
//     per action: u8 freq (× 250) + i16 ev (× 20 chips; -32768 = NA)
// A chunk file = 'TLPK' magic + u8 version + u32 nodeCount + node records,
// gzipped on disk/wire (gunzip before calling [decodeChunk]).

import 'dart:convert';
import 'dart:typed_data';

// ── Format constants (v1) ────────────────────────────────────────────────────

const int kPackVersion = 1;
const int kFreqScale = 250; // u8 0..250
const int kEquityScale = 250; // u8 0..250; 255 = NA
const int kEquityNa = 255;
const int kReachScale = 65535; // u16
const double kEvScale = 20; // i16 = chips × 20 (0.05-chip resolution at pot 10)
const int kEvNa = -32768;

const List<int> kPackMagic = [0x54, 0x4C, 0x50, 0x4B]; // 'TLPK'

// ── Decoded value types ──────────────────────────────────────────────────────

/// One decoded action node.
class PackNode {
  final String path;
  final int street; // 0 flop, 1 turn, 2 river
  final bool actorIsOop;
  final double potBefore;
  final double toCall;
  final double behind;
  final List<String> actions;
  final List<PackCombo> combos;
  PackNode({
    required this.path,
    required this.street,
    required this.actorIsOop,
    required this.potBefore,
    required this.toCall,
    required this.behind,
    required this.actions,
    required this.combos,
  });
}

class PackCombo {
  final int comboId;
  final double reach; // 0–1
  final double? equity; // 0–1, null = NA
  final double? evPassive; // chips, null = NA
  final List<double> freqs; // aligned to node actions, 0–1
  final List<double?> evs; // aligned to node actions, chips, null = NA
  PackCombo({
    required this.comboId,
    required this.reach,
    required this.equity,
    required this.evPassive,
    required this.freqs,
    required this.evs,
  });
}

// ── Decoder ──────────────────────────────────────────────────────────────────

class _Br {
  final Uint8List d;
  final ByteData v;
  int o = 0;
  _Br(List<int> raw)
      : d = raw is Uint8List ? raw : Uint8List.fromList(raw),
        v = ByteData.sublistView(
            raw is Uint8List ? raw : Uint8List.fromList(raw));

  int u8() => d[o++];
  int u16() {
    final x = v.getUint16(o, Endian.little);
    o += 2;
    return x;
  }

  int i16() {
    final x = v.getInt16(o, Endian.little);
    o += 2;
    return x;
  }

  int u32() {
    final x = v.getUint32(o, Endian.little);
    o += 4;
    return x;
  }

  double f32() {
    final x = v.getFloat32(o, Endian.little);
    o += 4;
    return x;
  }

  String shortStr() {
    final n = u8();
    final s = utf8.decode(d.sublist(o, o + n));
    o += n;
    return s;
  }

  String str16() {
    final n = u16();
    final s = utf8.decode(d.sublist(o, o + n));
    o += n;
    return s;
  }
}

/// Decode one UNCOMPRESSED chunk (gunzip the .bin.gz first).
List<PackNode> decodeChunk(List<int> raw) {
  final r = _Br(raw);
  for (final m in kPackMagic) {
    if (r.u8() != m) throw const FormatException('bad pack chunk magic');
  }
  final version = r.u8();
  if (version != kPackVersion) {
    throw FormatException('unsupported pack version $version');
  }
  final nodeCount = r.u32();
  final nodes = <PackNode>[];
  for (var n = 0; n < nodeCount; n++) {
    final path = r.str16();
    final street = r.u8();
    final actor = r.u8();
    final potBefore = r.f32();
    final toCall = r.f32();
    final behind = r.f32();
    final nActions = r.u8();
    final actions = [for (var a = 0; a < nActions; a++) r.shortStr()];
    final nCombos = r.u16();
    final combos = <PackCombo>[];
    for (var c = 0; c < nCombos; c++) {
      final id = r.u16();
      final reach = r.u16() / kReachScale;
      final eqRaw = r.u8();
      final pasRaw = r.i16();
      final freqs = <double>[];
      final evs = <double?>[];
      for (var a = 0; a < nActions; a++) {
        freqs.add(r.u8() / kFreqScale);
        final ev = r.i16();
        evs.add(ev == kEvNa ? null : ev / kEvScale);
      }
      combos.add(PackCombo(
        comboId: id,
        reach: reach,
        equity: eqRaw == kEquityNa ? null : eqRaw / kEquityScale,
        evPassive: pasRaw == kEvNa ? null : pasRaw / kEvScale,
        freqs: freqs,
        evs: evs,
      ));
    }
    nodes.add(PackNode(
      path: path,
      street: street,
      actorIsOop: actor == 0,
      potBefore: potBefore,
      toCall: toCall,
      behind: behind,
      actions: actions,
      combos: combos,
    ));
  }
  return nodes;
}
