// GTO Explorer — navigation state: which spot is open, the decoded flop chunk,
// and the cursor (action path) within it. Phase 1 is FLOP-ONLY: turn/river
// navigation lands with the lazy-chunk work (Phase 2).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../explorer/explorer_client.dart';
import '../explorer/pack_codec.dart';
import '../explorer/pack_manifest.dart';
import '../explorer/pack_source.dart';

class ExplorerState {
  final bool scanning; // initial spot discovery in flight
  final List<ExplorerSpotRef> spots;
  final ExplorerSpotRef? spot;
  final PackManifest? manifest;
  final List<PackNode>? flopNodes;
  final List<String> path; // action steps from the flop root
  final bool loading; // spot/chunk load in flight
  final String? error;

  const ExplorerState({
    this.scanning = false,
    this.spots = const [],
    this.spot,
    this.manifest,
    this.flopNodes,
    this.path = const [],
    this.loading = false,
    this.error,
  });

  ExplorerState copyWith({
    bool? scanning,
    List<ExplorerSpotRef>? spots,
    ExplorerSpotRef? spot,
    PackManifest? manifest,
    List<PackNode>? flopNodes,
    List<String>? path,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return ExplorerState(
      scanning: scanning ?? this.scanning,
      spots: spots ?? this.spots,
      spot: spot ?? this.spot,
      manifest: manifest ?? this.manifest,
      flopNodes: flopNodes ?? this.flopNodes,
      path: path ?? this.path,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// The node the cursor points at, or null (street closed / hand over / not
  /// loaded). Node paths are the '/'-joined action steps from the root.
  PackNode? get currentNode {
    final nodes = flopNodes;
    if (nodes == null) return null;
    final key = path.join('/');
    for (final n in nodes) {
      if (n.path == key) return n;
    }
    return null;
  }
}

class ExplorerNotifier extends StateNotifier<ExplorerState> {
  ExplorerNotifier() : super(const ExplorerState());

  ExplorerPackClient? _client;

  /// Discover browsable spots (local packs dir in dev; hosted index later).
  Future<void> init() async {
    if (state.scanning || state.spots.isNotEmpty) return;
    state = state.copyWith(scanning: true, clearError: true);
    final root = defaultPacksRoot();
    final spots = root == null ? const <ExplorerSpotRef>[] : await scanLocalPacks(root);
    state = state.copyWith(scanning: false, spots: spots);
    if (spots.isNotEmpty) await selectSpot(spots.first);
  }

  Future<void> selectSpot(ExplorerSpotRef spot) async {
    state = state.copyWith(
        spot: spot, loading: true, path: const [], flopNodes: null,
        clearError: true);
    try {
      final client = ExplorerPackClient(spot.source);
      final manifest = await client.manifest();
      final nodes = await client.chunk('flop');
      if (!mounted || state.spot != spot) return;
      _client = client;
      state = state.copyWith(
          manifest: manifest, flopNodes: nodes, loading: false);
    } catch (e) {
      if (!mounted || state.spot != spot) return;
      _client = null;
      state = state.copyWith(loading: false, error: 'Could not load spot: $e');
    }
  }

  /// The client for the open spot (turn/river chunks — Phase 2).
  ExplorerPackClient? get client => _client;

  void push(String action) =>
      state = state.copyWith(path: [...state.path, action]);

  /// Truncate the cursor to the first [n] steps (0 = back to the root).
  /// Clamped both ways: a caller computing `path.length - 1` on an empty path
  /// passes -1, and sublist(0, -1) throws RangeError.
  void popTo(int n) {
    if (n < 0 || n >= state.path.length) return;
    state = state.copyWith(path: state.path.sublist(0, n));
  }
}

final explorerProvider =
    StateNotifierProvider<ExplorerNotifier, ExplorerState>(
        (ref) => ExplorerNotifier());
