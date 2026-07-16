// GTO Explorer — navigation state: which spot is open, the RECORDED LINE of
// the hand, and a CURSOR within it.
//
// The line (actions + '@Ah' chance steps) is persistent — reaching showdown
// and tapping any earlier box just moves the cursor to inspect that decision;
// nothing resets. Editing (choosing a different action at the cursor) rewrites
// the line from that point and REGROWS the old tail, keeping every subsequent
// step that is still valid in the new branch (solver nodes offer different
// actions per branch, so an edit may or may not invalidate later streets).
// Runout cards are PINNED per street: they survive rewinds/edits, auto-deal on
// replay, and change only via their card box (in-place swap — the betting line
// survives because solver trees offer identical action structures on every
// runout card; sizes are pot-relative).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/explorer_config.dart';
import '../equity/card.dart';
import '../explorer/explorer_client.dart';
import '../explorer/http_packs.dart';
import '../explorer/pack_codec.dart';
import '../explorer/pack_manifest.dart';
import '../explorer/pack_source.dart';
import '../explorer/root_equity.dart';
import '../services/analytics_service.dart';

class ExplorerState {
  final bool scanning; // initial spot discovery in flight
  final List<ExplorerSpotRef> spots;
  final ExplorerSpotRef? spot;
  final PackManifest? manifest;
  final List<PackNode>? flopNodes;

  /// Decoded chunks for the LINE's pinned runout (`turn/{turnCard}`,
  /// `river/{turnCard}{riverCard}`). Null until dealt / loading / absent.
  final List<PackNode>? turnNodes;
  final List<PackNode>? riverNodes;

  /// The RECORDED line: action steps + chance steps ('@Ah') from the flop
  /// root. Persistent — never truncated by navigation, only by edits.
  final List<String> line;

  /// How many steps of [line] are "played" from the viewer's standpoint. The
  /// node under inspection is the one reached by line[0..cursor). Always
  /// normalized to not rest ON a chance step.
  final int cursor;

  /// Pinned runout cards ('9s') — see the header note.
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
    this.line = const [],
    this.cursor = 0,
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
    List<String>? line,
    int? cursor,
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
      line: line ?? this.line,
      cursor: cursor ?? this.cursor,
      turnCard: clearPins ? null : (turnCard ?? this.turnCard),
      riverCard: clearPins ? null : (riverCard ?? this.riverCard),
      loading: loading ?? this.loading,
      chunkLoading: chunkLoading ?? this.chunkLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// The steps up to the cursor (the position being inspected).
  List<String> get prefix => line.sublist(0, cursor.clamp(0, line.length));

  /// Cards dealt WITHIN the cursor prefix, in deal order — drives the board
  /// shown in the grid/lens at the inspected position.
  List<String> get dealtCards => [
        for (final s in prefix)
          if (s.startsWith('@')) s.substring(1)
      ];

  List<PackNode>? _nodesForDealt(int dealt) => switch (dealt) {
        0 => flopNodes,
        1 => turnNodes,
        _ => riverNodes,
      };

  /// Node reached by [steps], or null (closed street / hand over / chunk
  /// missing).
  PackNode? nodeAt(List<String> steps) {
    var dealt = 0;
    for (final s in steps) {
      if (s.startsWith('@')) dealt++;
    }
    final nodes = _nodesForDealt(dealt);
    if (nodes == null) return null;
    final key = steps.join('/');
    for (final n in nodes) {
      if (n.path == key) return n;
    }
    return null;
  }

  /// The node under the cursor.
  PackNode? get currentNode => nodeAt(prefix);

  /// The recorded action at the cursor (the "as played" choice the decision
  /// box highlights), or null at the line's end.
  String? get recordedNext => cursor < line.length ? line[cursor] : null;

  bool get atLineEnd => cursor >= line.length;
}

class ExplorerNotifier extends StateNotifier<ExplorerState> {
  ExplorerNotifier() : super(const ExplorerState());

  ExplorerPackClient? _client;

  /// Discover browsable spots from the hosted index and/or the local
  /// `~/tlpacks` scan. In a DEBUG build local packs win (a dev iterating on
  /// freshly-generated packs shouldn't be silently served the older hosted
  /// set); in release, hosted wins (there are no local packs on web/mobile
  /// anyway). Both sources are failure-tolerant → an empty list just hides the
  /// Study tab, never an error.
  Future<void> init() async {
    if (state.scanning || state.spots.isNotEmpty) return;
    state = state.copyWith(scanning: true, clearError: true);

    Future<List<ExplorerSpotRef>> local() async {
      final root = defaultPacksRoot();
      return root == null ? const [] : scanLocalPacks(root);
    }

    Future<List<ExplorerSpotRef>> hosted() async =>
        kPacksBaseUrl.isEmpty ? const [] : fetchHostedSpots(kPacksBaseUrl);

    var spots = await (kDebugMode ? local() : hosted());
    if (spots.isEmpty) spots = await (kDebugMode ? hosted() : local());

    state = state.copyWith(scanning: false, spots: spots);
    // The app-start default load is NOT user engagement — don't count it.
    if (spots.isNotEmpty) await selectSpot(spots.first, userInitiated: false);
  }

  Future<void> selectSpot(ExplorerSpotRef spot,
      {bool userInitiated = true}) async {
    state = state.copyWith(
        spot: spot,
        loading: true,
        line: const [],
        cursor: 0,
        flopNodes: null,
        clearTurn: true,
        clearRiver: true,
        clearPins: true, // pins are per-board
        // Reset chunkLoading too: a street-chunk fetch made stale by this
        // spot switch early-returns WITHOUT clearing it, and a stuck flag
        // wedges _streetClosed in an infinite spinner (review finding).
        chunkLoading: false,
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
      if (userInitiated) {
        AnalyticsService.explorerSpotLoaded(
            scenario: spot.scenario, spr: spot.spr);
      }
    } catch (e) {
      if (!mounted || state.spot != spot) return;
      _client = null;
      state = state.copyWith(loading: false, error: 'Could not load spot: $e');
    }
  }

  /// Clear the recorded postflop line back to the flop root — keeps the loaded
  /// spot (board + manifest + flop nodes), drops the line, cursor, pinned
  /// runout and its chunks. Backs the strip's "Reset" (rewind to preflop).
  void resetLine() {
    state = state.copyWith(
      line: const [],
      cursor: 0,
      clearTurn: true,
      clearRiver: true,
      clearPins: true,
      chunkLoading: false,
      clearError: true,
    );
  }

  /// Move the viewer to step [i] of the line WITHOUT changing the line — the
  /// "replay any point, even after showdown" navigation. Normalizes forward
  /// off chance steps (they are not decisions).
  void setCursor(int i) {
    var c = i.clamp(0, state.line.length);
    while (c < state.line.length && state.line[c].startsWith('@')) {
      c++;
    }
    state = state.copyWith(cursor: c, clearError: true);
  }

  /// Step the cursor BACK one decision. setCursor normalizes FORWARD, so
  /// `setCursor(cursor - 1)` over a chance step lands right back where it was
  /// (the Back button was a no-op after a dealt card — review finding);
  /// normalize BACKWARD instead.
  void stepBack() {
    var c = state.cursor - 1;
    while (c > 0 && state.line[c].startsWith('@')) {
      c--;
    }
    if (c < 0) c = 0;
    state = state.copyWith(cursor: c, clearError: true);
  }

  /// Take [action] at the cursor.
  ///  - Matches the recorded step → pure replay: the cursor advances (through
  ///    any following chance steps), the line is untouched.
  ///  - Differs (or the cursor is at the line's end) → the line is EDITED:
  ///    rewritten up to the cursor + the new action, then the old tail is
  ///    REGROWN — every subsequent recorded step that remains valid in the
  ///    new branch is kept (an edit may or may not invalidate later streets).
  Future<void> advance(String action) async {
    final s = state;
    if (s.recordedNext == action) {
      setCursor(s.cursor + 1);
      return;
    }
    final oldTail = s.cursor + 1 <= s.line.length
        ? s.line.sublist((s.cursor + 1).clamp(0, s.line.length))
        : const <String>[];
    final newLine = [...s.prefix, action];
    state = s.copyWith(line: newLine, cursor: newLine.length, clearError: true);
    await _regrowTail(oldTail, baseLine: newLine);
  }

  /// Deal [card] at the line's end (closed street): appends the chance step,
  /// pins the card for its street, advances the cursor through it, and
  /// fetches the runout's chunks.
  Future<void> pickCard(String card) async {
    final s = state;
    if (!s.atLineEnd) return; // mid-line cards change via setPinnedCard
    final dealt = [
      for (final x in s.line)
        if (x.startsWith('@')) x
    ].length;
    if (dealt >= 2) return;
    final newLine = [...s.line, '@$card'];
    state = s.copyWith(
      line: newLine,
      cursor: newLine.length,
      turnCard: dealt == 0 ? card : null,
      riverCard: dealt == 0 ? null : card,
      clearError: true,
    );
    await _loadChunksForLine();
  }

  /// Re-pin a street's card (the card-box tap): replaces the pin and swaps
  /// any matching chance step IN PLACE — the betting line survives; only the
  /// chunks re-fetch. Valid at any cursor position.
  Future<void> setPinnedCard(
      {required bool river, required String card}) async {
    final m = state.manifest;
    if (m == null) return;
    if (m.flop.split(' ').contains(card)) return;
    if (river && card == state.turnCard) return;
    if (!river && card == state.riverCard) return;
    final line = [...state.line];
    final chanceIdxs = [
      for (var i = 0; i < line.length; i++)
        if (line[i].startsWith('@')) i
    ];
    final pos = river ? 1 : 0;
    if (chanceIdxs.length > pos) line[chanceIdxs[pos]] = '@$card';
    state = state.copyWith(
      line: line,
      turnCard: river ? null : card,
      riverCard: river ? card : null,
      clearError: true,
    );
    await _loadChunksForLine();
  }

  /// Fetch the chunks the LINE's pinned runout requires, tolerating absent
  /// runouts (nodes stay null → the screen shows an unavailable state).
  Future<void> _loadChunksForLine() async {
    final client = _client;
    if (client == null) return;
    final t = state.turnCard;
    final r = state.riverCard;
    final expectedLine = state.line.join('/');
    bool stale() =>
        !mounted ||
        state.line.join('/') != expectedLine ||
        state.turnCard != t ||
        state.riverCard != r;
    state =
        state.copyWith(chunkLoading: true, clearTurn: true, clearRiver: true);
    List<PackNode>? turn;
    List<PackNode>? river;
    try {
      if (t != null) turn = await client.chunk('turn/$t');
      if (t != null && r != null) river = await client.chunk('river/$t$r');
    } catch (_) {
      // Thin/absent runout — keep whatever loaded.
    }
    if (stale()) return;
    state = state.copyWith(
        turnNodes: turn, riverNodes: river, chunkLoading: false);
  }

  /// Is the CURRENT street of [steps] cleanly closed (bet matched by a call,
  /// or checked through heads-up)? Structural — a missing/terminal node must
  /// not read as "closed" (that conflation once regrew a card onto an
  /// unresponded bet).
  static bool _streetIsClosed(List<String> steps) {
    final street =
        steps.reversed.takeWhile((s) => !s.startsWith('@')).toList();
    if (street.isEmpty) return false;
    final last = street.first.toUpperCase(); // reversed → first = latest
    if (last.startsWith('CALL')) return true;
    return street.length >= 2 &&
        street.every((s) => s.toUpperCase().startsWith('CHECK'));
  }

  /// After an edit, regrow the old tail: append each old step while it stays
  /// valid in the new branch — an action must be offered by the node reached;
  /// a chance step needs a cleanly closed street (and never follows a fold).
  /// [baseLine] is the edited line this regrow belongs to: the await below is
  /// a real gap (chunk IO), and grafting a stale tail onto a line the user
  /// has ALREADY re-edited would fabricate steps they never chose.
  Future<void> _regrowTail(List<String> oldTail,
      {required List<String> baseLine}) async {
    if (oldTail.isEmpty) return;
    await _loadChunksForLine(); // chunks for the pinned runout, if any
    if (!mounted || state.line.join('/') != baseLine.join('/')) return;
    final grown = [...state.line];
    var dealtCount = [
      for (final x in grown)
        if (x.startsWith('@')) x
    ].length;
    for (final step in oldTail) {
      if (step.startsWith('@')) {
        if (!_streetIsClosed(grown) || dealtCount >= 2) break;
        grown.add(step);
        dealtCount++;
      } else {
        final node = state.nodeAt(grown);
        if (node == null || !node.actions.contains(step)) break;
        grown.add(step);
      }
    }
    if (grown.length == state.line.length) return;
    state = state.copyWith(line: grown);
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
}

final explorerProvider = StateNotifierProvider<ExplorerNotifier, ExplorerState>(
    (ref) => ExplorerNotifier());

/// Focus/maximize mode for the Study tab: when true the app chrome (the GTO
/// Study app bar + the bottom navigation) hides so the spot gets the full
/// window. Toggled from the Study screen; MainNavigation watches it to drop the
/// bottom nav.
final studyMaximizedProvider = StateProvider<bool>((ref) => false);
