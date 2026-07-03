// GTO Explorer — navigation state: which spot is open, the decoded chunks for
// the streets on the current line, and the cursor (action path + dealt cards)
// within them. Phase 2: full flop → turn → river navigation; turn/river chunks
// are LAZILY fetched when a card is picked (chance steps are '@Ah' path steps,
// matching the pack's node paths).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../equity/card.dart';
import '../explorer/explorer_client.dart';
import '../explorer/pack_codec.dart';
import '../explorer/pack_manifest.dart';
import '../explorer/pack_source.dart';
import '../explorer/root_equity.dart';

class ExplorerState {
  final bool scanning; // initial spot discovery in flight
  final List<ExplorerSpotRef> spots;
  final ExplorerSpotRef? spot;
  final PackManifest? manifest;
  final List<PackNode>? flopNodes;

  /// Decoded chunk for the CURRENT line's turn card (null until one is
  /// picked), and likewise for the river. Replaced when the line changes.
  final List<PackNode>? turnNodes;
  final List<PackNode>? riverNodes;

  /// Cursor: action steps + chance steps ('@Ah') from the flop root.
  final List<String> path;

  /// PINNED runout cards ('9s'). Independent of the cursor: they survive
  /// rewinds (replaying a street auto-deals them — the user never re-enters
  /// cards) and only change when explicitly re-picked via their card box.
  final String? turnCard;
  final String? riverCard;
  final bool loading; // spot load in flight
  final bool chunkLoading; // street-chunk fetch in flight
  final String? error;

  const ExplorerState({
    this.scanning = false,
    this.spots = const [],
    this.spot,
    this.manifest,
    this.flopNodes,
    this.turnNodes,
    this.riverNodes,
    this.path = const [],
    this.turnCard,
    this.riverCard,
    this.loading = false,
    this.chunkLoading = false,
    this.error,
  });

  ExplorerState copyWith({
    bool? scanning,
    List<ExplorerSpotRef>? spots,
    ExplorerSpotRef? spot,
    PackManifest? manifest,
    List<PackNode>? flopNodes,
    List<PackNode>? turnNodes,
    List<PackNode>? riverNodes,
    List<String>? path,
    String? turnCard,
    String? riverCard,
    bool? loading,
    bool? chunkLoading,
    String? error,
    bool clearError = false,
    bool clearTurn = false,
    bool clearRiver = false,
    bool clearPins = false,
  }) {
    return ExplorerState(
      scanning: scanning ?? this.scanning,
      spots: spots ?? this.spots,
      spot: spot ?? this.spot,
      manifest: manifest ?? this.manifest,
      flopNodes: flopNodes ?? this.flopNodes,
      turnNodes: clearTurn ? null : (turnNodes ?? this.turnNodes),
      riverNodes: clearRiver ? null : (riverNodes ?? this.riverNodes),
      path: path ?? this.path,
      turnCard: clearPins ? null : (turnCard ?? this.turnCard),
      riverCard: clearPins ? null : (riverCard ?? this.riverCard),
      loading: loading ?? this.loading,
      chunkLoading: chunkLoading ?? this.chunkLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Cards dealt on the current line, in deal order ('Ah', '3d').
  List<String> get dealtCards => [
        for (final s in path)
          if (s.startsWith('@')) s.substring(1)
      ];

  /// The node the cursor points at, or null (street closed / hand over /
  /// chunk not loaded). Node paths are the '/'-joined steps from the root;
  /// which chunk to search follows from how many cards have been dealt.
  PackNode? get currentNode {
    final nodes = switch (dealtCards.length) {
      0 => flopNodes,
      1 => turnNodes,
      _ => riverNodes,
    };
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
    final spots =
        root == null ? const <ExplorerSpotRef>[] : await scanLocalPacks(root);
    state = state.copyWith(scanning: false, spots: spots);
    if (spots.isNotEmpty) await selectSpot(spots.first);
  }

  Future<void> selectSpot(ExplorerSpotRef spot) async {
    state = state.copyWith(
        spot: spot,
        loading: true,
        path: const [],
        flopNodes: null,
        clearTurn: true,
        clearRiver: true,
        clearPins: true, // pins are per-board
        clearError: true);
    try {
      final client = ExplorerPackClient(spot.source);
      final manifest = await client.manifest();
      final nodes = await client.chunk('flop');
      if (!mounted || state.spot != spot) return;
      _client = client;
      _rootOppFuture = null; // per-spot cache
      _rootOppSpot = null;
      state =
          state.copyWith(manifest: manifest, flopNodes: nodes, loading: false);
    } catch (e) {
      if (!mounted || state.spot != spot) return;
      _client = null;
      state = state.copyWith(loading: false, error: 'Could not load spot: $e');
    }
  }

  void push(String action) =>
      state = state.copyWith(path: [...state.path, action]);

  /// Deal [card] ('Ah') on a closed street: appends the chance step, PINS the
  /// card for its street (so rewinds/replays never re-ask), and lazily fetches
  /// that runout's chunk (`turn/{card}` after 0 dealt cards,
  /// `river/{turn}{card}` after 1). A missing/failed chunk keeps the step (the
  /// screen shows a line-unavailable state with the strip as the way back).
  Future<void> pickCard(String card) async {
    final dealt = state.dealtCards;
    if (dealt.length >= 2) return; // river already dealt
    final newPath = [...state.path, '@$card'];
    state = state.copyWith(
      path: newPath,
      turnCard: dealt.isEmpty ? card : null,
      riverCard: dealt.isEmpty ? null : card,
      clearError: true,
    );
    await _loadChunksForPath();
  }

  /// Re-pin a street's card (the card-box tap): replaces the pin and, when the
  /// cursor's line already contains that chance step, swaps it IN PLACE — the
  /// betting line survives (solver trees offer identical action structures on
  /// every runout card; sizes are pot-relative) and only the chunks re-fetch.
  Future<void> setPinnedCard({required bool river, required String card}) async {
    final m = state.manifest;
    if (m == null) return;
    // Collisions are excluded in the picker UI; guard anyway.
    if (m.flop.split(' ').contains(card)) return;
    if (river && card == state.turnCard) return;
    if (!river && card == state.riverCard) return;
    final path = [...state.path];
    final chanceIdxs = [
      for (var i = 0; i < path.length; i++)
        if (path[i].startsWith('@')) i
    ];
    final pos = river ? 1 : 0;
    if (chanceIdxs.length > pos) path[chanceIdxs[pos]] = '@$card';
    state = state.copyWith(
      path: path,
      turnCard: river ? null : card,
      riverCard: river ? card : null,
      clearError: true,
    );
    await _loadChunksForPath();
  }

  /// Fetch the chunks the CURRENT path's dealt cards require (turn/river),
  /// tolerating absent runouts (currentNode stays null → unavailable state).
  Future<void> _loadChunksForPath() async {
    final client = _client;
    if (client == null) return;
    final dealt = state.dealtCards;
    final expected = state.path.join('/');
    bool stale() => !mounted || state.path.join('/') != expected;
    state = state.copyWith(chunkLoading: true, clearTurn: true, clearRiver: true);
    List<PackNode>? turn;
    List<PackNode>? river;
    try {
      if (dealt.isNotEmpty) turn = await client.chunk('turn/${dealt[0]}');
      if (dealt.length > 1) {
        river = await client.chunk('river/${dealt[0]}${dealt[1]}');
      }
    } catch (_) {
      // Thin/absent runout — keep whatever loaded; the screen shows the
      // unavailable state for the missing street.
    }
    if (stale()) return;
    state = state.copyWith(
        turnNodes: turn, riverNodes: river, chunkLoading: false);
  }

  /// The client for the open spot (prefetching, Phase 3+).
  ExplorerPackClient? get client => _client;

  Future<List<PackCombo>>? _rootOppFuture;
  ExplorerSpotRef? _rootOppSpot;

  /// Equity distribution for the player who has NOT acted at the flop root
  /// (the IP player) — the packs store no equity for them there, so it's
  /// Monte-Carlo'd on-device ONCE per spot (compute isolate) and cached.
  Future<List<PackCombo>> rootOpponentEquities() {
    final spot = state.spot;
    final manifest = state.manifest;
    if (spot == null || manifest == null) {
      return Future.value(const <PackCombo>[]);
    }
    if (_rootOppFuture != null && identical(_rootOppSpot, spot)) {
      return _rootOppFuture!;
    }
    _rootOppSpot = spot;
    return _rootOppFuture = compute(
      computeRootEquities,
      RootEquityPayload(
        heroCombos: manifest.ipCombos, // the flop root's actor is always OOP
        villainCombos: manifest.oopCombos,
        board: [for (final c in manifest.flop.split(' ')) parseCard(c)],
      ),
    );
  }

  /// Truncate the cursor to the first [n] steps (0 = back to the flop root).
  /// Clamped both ways: a caller computing `path.length - 1` on an empty path
  /// passes -1, and sublist(0, -1) throws RangeError. Dropping a chance step
  /// drops its street's nodes (the chunk stays warm in the client LRU, so
  /// re-dealing the same card is instant).
  void popTo(int n) {
    if (n < 0 || n >= state.path.length) return;
    final newPath = state.path.sublist(0, n);
    final dealt = [
      for (final s in newPath)
        if (s.startsWith('@')) s
    ].length;
    state = state.copyWith(
      path: newPath,
      clearTurn: dealt < 1,
      clearRiver: dealt < 2,
    );
  }
}

final explorerProvider = StateNotifierProvider<ExplorerNotifier, ExplorerState>(
    (ref) => ExplorerNotifier());
