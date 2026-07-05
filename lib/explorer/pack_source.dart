// GTO Explorer — where pack bytes come from.
//
// The client reads a pack through a [PackSource] (paths relative to one spot's
// root: 'manifest.json', 'flop.bin.gz', 'turn/Ah.bin.gz', …). Sources:
//  - LocalDirPackSource + scanLocalPacks (dart:io — desktop/mobile dev against
//    a pulled packs directory; stubbed out on web via conditional export).
//  - A hosted HTTP/Supabase-Storage source arrives with the Phase 1 hosting
//    step; the client is source-agnostic.

import 'dart:typed_data';

export 'local_packs_stub.dart' if (dart.library.io) 'local_packs_io.dart';

abstract class PackSource {
  /// Read a file within the spot's pack (throws on missing).
  Future<Uint8List> read(String relPath);
}

/// One browsable spot: labels for the picker + the source to read it from.
class ExplorerSpotRef {
  final String scenario;
  final String flop; // 'Ks 9h 4c'
  final String spr; // regime name
  final PackSource source;
  ExplorerSpotRef({
    required this.scenario,
    required this.flop,
    required this.spr,
    required this.source,
  });

  String get label => '$flop · $spr';
}
