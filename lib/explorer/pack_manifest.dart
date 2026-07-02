// GTO Explorer — pack manifest model (pure Dart, web-safe).
//
// A pack's manifest.json describes one solved spot: meta (scenario, flop, SPR
// regime, pot/stacks), the per-position combo lists that chunk records index
// into, and the chunk index (id → file). Written by the generator
// (tool/solver/explorer_pack.dart); parsed here defensively — a malformed
// hosted file must fail with a FormatException, not a random cast error.

class PackManifest {
  final int version;
  final String scenario;
  final String spr; // regime name, e.g. 'shallow'
  final String flop; // 'Ks 9h 4c'
  final double pot0;
  final double effStack;
  final List<String> oopCombos; // comboId → 'AhKs'
  final List<String> ipCombos;
  final Map<String, PackChunkInfo> chunks; // chunk id → info

  PackManifest({
    required this.version,
    required this.scenario,
    required this.spr,
    required this.flop,
    required this.pot0,
    required this.effStack,
    required this.oopCombos,
    required this.ipCombos,
    required this.chunks,
  });

  List<String> combosFor({required bool oop}) => oop ? oopCombos : ipCombos;

  factory PackManifest.fromJson(Map<String, dynamic> j) {
    final version = j['version'];
    final combos = j['combos'];
    final chunks = j['chunks'];
    if (version is! int || combos is! Map || chunks is! Map) {
      throw const FormatException('pack manifest: missing version/combos/chunks');
    }
    List<String> comboList(String key) {
      final v = combos[key];
      if (v is! List) throw FormatException('pack manifest: bad combos.$key');
      return v.map((e) => e.toString()).toList();
    }

    return PackManifest(
      version: version,
      scenario: j['scenario']?.toString() ?? '?',
      spr: j['spr']?.toString() ?? '?',
      flop: j['flop']?.toString() ?? '?',
      pot0: (j['pot0'] as num?)?.toDouble() ?? 0,
      effStack: (j['eff_stack'] as num?)?.toDouble() ?? 0,
      oopCombos: comboList('oop'),
      ipCombos: comboList('ip'),
      chunks: {
        for (final e in chunks.entries)
          e.key.toString(): PackChunkInfo.fromJson(e.value as Map),
      },
    );
  }
}

class PackChunkInfo {
  final String file; // relative to the pack root, e.g. 'turn/Ah.bin.gz'
  final int nodes;
  final int gz;
  PackChunkInfo({required this.file, required this.nodes, required this.gz});

  factory PackChunkInfo.fromJson(Map j) => PackChunkInfo(
        file: j['file']?.toString() ?? '',
        nodes: (j['nodes'] as num?)?.toInt() ?? 0,
        gz: (j['gz'] as num?)?.toInt() ?? 0,
      );
}
