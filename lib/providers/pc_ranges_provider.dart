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
  final raw = await rootBundle.loadString('assets/pc_ranges.json');
  return compute(PcRangeLibrary.fromJsonString, raw);
});

/// Equity-calculator preset list derived from the library; null while loading
/// (the range editor falls back to the legacy presets).
final pcEquityPresetsProvider = Provider<List<GtoPreset>?>((ref) {
  final lib = ref.watch(pcRangeLibraryProvider).valueOrNull;
  return lib == null ? null : pcEquityPresets(lib);
});
