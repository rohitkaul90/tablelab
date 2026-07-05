// GTO Explorer — web stub for the dart:io local-packs source (see the
// conditional export in pack_source.dart). On web there is no local
// filesystem; hosted packs arrive with the Phase 1 hosting step.

import 'dart:typed_data';

import 'pack_source.dart';

String? defaultPacksRoot() => null;

class LocalDirPackSource implements PackSource {
  final String root;
  LocalDirPackSource(this.root);

  @override
  Future<Uint8List> read(String relPath) =>
      throw UnsupportedError('local packs are not available on web');
}

Future<List<ExplorerSpotRef>> scanLocalPacks(String root) async => const [];
