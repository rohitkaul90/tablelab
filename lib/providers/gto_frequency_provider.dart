import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../equity/gto_frequency_library.dart';

/// Loads the offline-solved GTO frequency library (assets/gto_freq_library.json)
/// once and caches it for the lifetime of the app. The hand-analysis path reads
/// this and passes the [GtoFrequencyLibrary] into `equityCheckFacts` so the
/// coaching can be grounded with `[HEURISTIC — GTO frequency]` lines.
///
/// `keepAlive` so the (628 KB) parse happens once, not per analysis. The decode +
/// group-indexing is offloaded to a background isolate via `compute()` so the
/// first analysis never janks the UI thread. Loading is kept here (Flutter
/// `rootBundle`) so `lib/equity/` stays pure / isolate-safe; the eval baker loads
/// the same JSON via dart:io instead.
final gtoFrequencyLibraryProvider =
    FutureProvider<GtoFrequencyLibrary>((ref) async {
  ref.keepAlive();
  final json = await rootBundle.loadString('assets/gto_freq_library.json');
  return compute(GtoFrequencyLibrary.fromJsonString, json);
});
