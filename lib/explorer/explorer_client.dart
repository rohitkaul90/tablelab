// GTO Explorer — pack client: manifest + chunk loading for one spot.
//
// Fetches bytes through a [PackSource], gunzips (package:archive — pure Dart,
// web-safe) and decodes the binary chunk inside a compute() isolate so a big
// chunk never janks the UI thread (on web compute() degrades to synchronous,
// which is fine at flop-chunk sizes). Keeps a small LRU of decoded chunks —
// street navigation revisits the same chunks constantly.

import 'dart:collection';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'pack_codec.dart';
import 'pack_manifest.dart';
import 'pack_source.dart';

/// Top-level for compute(): gunzip + decode in one isolate hop.
List<PackNode> decodeGzChunk(Uint8List gz) =>
    decodeChunk(GZipDecoder().decodeBytes(gz));

class ExplorerPackClient {
  final PackSource source;
  ExplorerPackClient(this.source);

  PackManifest? _manifest;
  // Insertion-ordered map used as an LRU (moved-to-end on hit).
  final LinkedHashMap<String, List<PackNode>> _chunks = LinkedHashMap();
  static const int _cacheMax = 16;

  Future<PackManifest> manifest() async {
    return _manifest ??= PackManifest.fromJson(
        jsonDecode(utf8.decode(await source.read('manifest.json')))
            as Map<String, dynamic>);
  }

  /// Decoded nodes of one chunk ('flop', 'turn/Ah', 'river/Ah2c').
  Future<List<PackNode>> chunk(String id) async {
    final cached = _chunks.remove(id);
    if (cached != null) {
      _chunks[id] = cached; // re-insert = most recently used
      return cached;
    }
    final m = await manifest();
    final info = m.chunks[id];
    if (info == null) {
      throw StateError('pack has no chunk "$id" (${m.flop} ${m.spr})');
    }
    final gz = await source.read(info.file);
    final nodes = await compute(decodeGzChunk, gz);
    _chunks[id] = nodes;
    while (_chunks.length > _cacheMax) {
      _chunks.remove(_chunks.keys.first);
    }
    return nodes;
  }

  /// Drop every cached chunk except [chunkIds] (the manifest is kept). The
  /// notifier trims an OUTGOING spot's client to its flop chunk — the
  /// cross-spot client LRU (8 clients) must not pin 8× this cache's worth of
  /// decoded turn/river chunks; a return visit re-fetches those lazily.
  void retainOnly(Set<String> chunkIds) {
    _chunks.removeWhere((id, _) => !chunkIds.contains(id));
  }
}
