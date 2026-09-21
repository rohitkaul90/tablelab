import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../equity/pc_equity_presets.dart';
import '../equity/gto_ranges.dart' show GtoPreset;
import '../equity/weighted_ranges.dart';

/// The PC weighted range library, parsed off the main thread. Loaded once per
/// app run; consumers use `.valueOrNull` and fall back to legacy charts while
/// it loads (or if the asset is broken — `skippedCharts` keeps a broken
/// regeneration observable rather than fatal).
final pcRangeLibraryProvider = FutureProvider<PcRangeLibrary>((ref) async {
  // cache:false — without it the 3.5MB raw JSON string stays pinned in the
  // asset cache for the app's lifetime alongside the parsed library. (On web
  // compute() runs synchronously, so the one-time parse lands on the UI
  // thread at screen-entry warm-up — a known, accepted hitch.)
  final raw =
      await rootBundle.loadString('assets/pc_ranges.json', cache: false);
  return compute(PcRangeLibrary.fromJsonString, raw);
});

/// Equity-calculator preset list derived from the library; null while loading
/// AND null when the derived list is empty (a degenerate asset must fall back
/// to the legacy presets, not present an empty picker).
final pcEquityPresetsProvider = Provider<List<GtoPreset>?>((ref) {
  final lib = ref.watch(pcRangeLibraryProvider).valueOrNull;
  if (lib == null) return null;
  final presets = pcEquityPresets(lib);
  return presets.isEmpty ? null : presets;
});
