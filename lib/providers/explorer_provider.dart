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
// runout card; sizes are pot-relative). One exception: CHANGING the turn card
// CLEARS the pinned river (upstream change resets downstream — and it removes
// the suit-ambiguity class where a turn transposition could move a later pin);
// re-picking the identical turn keeps the river.

import 'dart:collection';

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
  final bool scanning; // initial catalog discovery in flight

  /// The scenario catalog (tiny — one row per scenario). Empty = no packs
  /// discoverable → the Study tab stays hidden.
  final List<ScenarioSummary> catalog;

  /// Precomputed key set of [catalog] — the per-build "does this scenario have
  /// packs?" check must be O(1), not a list scan.
  final Set<String> scenarioKeys;

  /// Lazily-loaded spot lists, keyed by scenario. A key's ABSENCE means "not
  /// fetched yet" (or failed — see [scenarioErrors]), never "no spots".
  final Map<String, List<ExplorerSpotRef>> scenarioSpots;

  /// Scenarios whose index fetch failed (retryable via ensureScenario).
  final Set<String> scenarioErrors;

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
    this.catalog = const [],
    this.scenarioKeys = const {},
    this.scenarioSpots = const {},
    this.scenarioErrors = const {},
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

  /// The loaded spots of [sc], or [] when not (yet) fetched.
  List<ExplorerSpotRef> spotsFor(String sc) => scenarioSpots[sc] ?? const [];

  ExplorerState copyWith({
    bool? scanning,
    List<ScenarioSummary>? catalog,
    Set<String>? scenarioKeys,
    Map<String, List<ExplorerSpotRef>>? scenarioSpots,
    Set<String>? scenarioErrors,
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
    bool clearRiverPin = false,
  }) {
    return ExplorerState(
      scanning: scanning ?? this.scanning,
      catalog: catalog ?? this.catalog,
      scenarioKeys: scenarioKeys ?? this.scenarioKeys,
      scenarioSpots: scenarioSpots ?? this.scenarioSpots,
      scenarioErrors: scenarioErrors ?? this.scenarioErrors,
      spot: spot ?? this.spot,
      manifest: manifest ?? this.manifest,
      flopNodes: flopNodes ?? this.flopNodes,
      turnNodes: clearTurn ? null : (turnNodes ?? this.turnNodes),
      riverNodes: clearRiver ? null : (riverNodes ?? this.riverNodes),
      line: line ?? this.line,
      cursor: cursor ?? this.cursor,
      turnCard: clearPins ? null : (turnCard ?? this.turnCard),
      riverCard: clearPins || clearRiverPin
          ? null
          : (riverCard ?? this.riverCard),
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

/// Discovery over the local `~/tlpacks` scan: one scan (memoized), catalog
/// synthesized by grouping the scanned spots per scenario. Never throws — an
/// unreadable dir is just an empty catalog (the local-scan contract).
class LocalSpotDiscovery implements SpotDiscovery {
  Future<Map<String, List<ExplorerSpotRef>>>? _scan;

  Future<Map<String, List<ExplorerSpotRef>>> _grouped() {
    return _scan ??= () async {
      final root = defaultPacksRoot();
      final spots = root == null
          ? const <ExplorerSpotRef>[]
          : await scanLocalPacks(root); // already spotSortKey-sorted
      final grouped = <String, List<ExplorerSpotRef>>{};
      for (final s in spots) {
        (grouped[s.scenario] ??= []).add(s);
      }
      return grouped;
    }();
  }

  @override
  Future<List<ScenarioSummary>> catalog() async {
    final grouped = await _grouped();
    return [
      for (final e in grouped.entries)
        ScenarioSummary(key: e.key, spotCount: e.value.length),
    ]..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  Future<List<ExplorerSpotRef>> scenarioSpots(String key) async =>
      (await _grouped())[key] ?? const [];
}

class ExplorerNotifier extends StateNotifier<ExplorerState> {
  ExplorerNotifier() : super(const ExplorerState());

  ExplorerPackClient? _client;

  /// The discovery init() settled on (the one whose catalog was non-empty).
  SpotDiscovery? _discovery;

  /// Test seam: when set, init() uses this instead of the local/hosted pair.
  @visibleForTesting
  SpotDiscovery? debugDiscovery;

  /// In-flight per-scenario index fetches — concurrent ensureScenario calls
  /// share one future; a FAILED fetch is removed so the next call retries.
  final Map<String, Future<void>> _scenarioFutures = {};

  /// Decoded-pack clients keyed by spot id, so a board-hop A→B→A serves A's
  /// manifest + chunks from memory instead of refetching (the old code built a
  /// fresh client per selectSpot). Insertion-ordered map used as an LRU.
  final LinkedHashMap<String, ExplorerPackClient> _clients = LinkedHashMap();
  static const int _clientCacheMax = 8;

  @visibleForTesting
  int get debugClientCacheCount => _clients.length;

  /// Discover the scenario CATALOG from the hosted host and/or the local
  /// `~/tlpacks` scan, then lazily load only the first scenario and auto-select
  /// its first spot. In a DEBUG build local packs win (a dev iterating on
  /// freshly-generated packs shouldn't be silently served the older hosted
  /// set); in release, hosted wins (there are no local packs on web/mobile
  /// anyway). Catalog discovery is failure-tolerant → an empty catalog just
  /// hides the Study tab, never an error (and a later init() retries).
  Future<void> init() async {
    if (state.scanning || state.catalog.isNotEmpty) return;
    state = state.copyWith(scanning: true, clearError: true);

    SpotDiscovery? found;
    List<ScenarioSummary> catalog = const [];
    final candidates = debugDiscovery != null
        ? <SpotDiscovery>[debugDiscovery!]
        : <SpotDiscovery>[
            if (kDebugMode) LocalSpotDiscovery(),
            if (kPacksBaseUrl.isNotEmpty) HostedSpotDiscovery(kPacksBaseUrl),
            if (!kDebugMode) LocalSpotDiscovery(),
          ];
    try {
      for (final d in candidates) {
        catalog = await d.catalog();
        if (catalog.isNotEmpty) {
          found = d;
          break;
        }
      }
    } catch (_) {
      // catalog() promises never to throw, but a test/future source might —
      // a leaked throw must not leave `scanning` stuck true (Study tab
      // permanently hidden with no retry path).
      found = null;
    }
    if (!mounted) return;
    if (found == null) {
      state = state.copyWith(scanning: false);
      return; // catalog stays empty → a later init() retries
    }
    _discovery = found;
    state = state.copyWith(
      catalog: catalog,
      scenarioKeys: {for (final s in catalog) s.key},
    );
    // Load only the FIRST scenario up front for the auto-select — the rest
    // fetch on demand. `scanning` stays true through it so the screen shows
    // one continuous spinner, not a flash of "pick a board".
    await ensureScenario(catalog.first.key);
    if (!mounted) return;
    final first = state.spotsFor(catalog.first.key);
    state = state.copyWith(scanning: false);
    // Race guard: a concurrent selectSpot (deep link, test) wins.
    if (first.isNotEmpty && state.spot == null) {
      await selectSpot(first.first);
    }
  }

  /// Fetch [key]'s spot list if it isn't loaded. Concurrent calls share one
  /// fetch; a failure records [ExplorerState.scenarioErrors] (and clears the
  /// shared future so the next call RETRIES) instead of throwing.
  Future<void> ensureScenario(String key) {
    if (state.scenarioSpots.containsKey(key)) return Future.value();
    // Pre-init (no discovery yet): nothing to fetch — and the no-op must NOT
    // be cached in _scenarioFutures. A synchronous no-op future's cleanup ran
    // BEFORE ??= stored it, permanently wedging the key on a dead completed
    // future (review finding; reachable in debug where the tab always shows).
    final discovery = _discovery;
    if (discovery == null) return Future.value();
    return _scenarioFutures[key] ??= _fetchScenario(discovery, key);
  }

  /// ensureScenario + return the loaded list. THROWS when the index fetch
  /// failed — the board-picker sheet must distinguish "fetch failed" (show
  /// Retry) from a genuinely empty scenario. Safe to call from a sheet that
  /// outlives its screen (the notifier is app-scoped).
  Future<List<ExplorerSpotRef>> loadScenarioSpots(String key) async {
    await ensureScenario(key);
    final spots = state.scenarioSpots[key];
    if (spots == null) throw StateError('scenario index failed: $key');
    return spots;
  }

  Future<void> _fetchScenario(SpotDiscovery discovery, String key) async {
    try {
      final spots = await discovery.scenarioSpots(key);
      _scenarioFutures.remove(key); // loaded → the containsKey guard takes over
      if (!mounted) return;
      state = state.copyWith(
        scenarioSpots: {...state.scenarioSpots, key: spots},
        scenarioErrors: {...state.scenarioErrors}..remove(key),
      );
    } catch (_) {
      _scenarioFutures.remove(key); // retryable
      if (!mounted) return;
      state = state.copyWith(scenarioErrors: {...state.scenarioErrors, key});
    }
  }

  /// [userInitiated] gates the `explorer_spot_loaded` analytics event and
  /// FAILS CLOSED: it defaults to false so only the explicit user actions
  /// (spot picker, board change, SPR/regime switch) count as engagement —
  /// the app-start auto-select and the error-screen Retry must not.
  Future<void> selectSpot(ExplorerSpotRef spot,
      {bool userInitiated = false}) async {
    // Trim the OUTGOING spot's client down to its flop chunk before it goes
    // into the LRU: a board-hop return still skips the manifest + flop
    // refetch, but 8 cached clients can't pin 8×16 decoded turn/river chunks.
    final prev = state.spot;
    final prevClient = _client;
    if (prev != null && prevClient != null && prev.id != spot.id) {
      prevClient.retainOnly(const {'flop'});
    }
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
    // Reuse a cached client (its manifest + chunk LRU) on a return visit —
    // a board-hop A→B→A must not refetch A's manifest/flop chunk.
    final cached = _clients.remove(spot.id);
    final client = cached ?? ExplorerPackClient(spot.source);
    try {
      final manifest = await client.manifest();
      final nodes = await client.chunk('flop');
      // Cache even when the load raced a newer spot switch (the completed
      // client is still valid for a later return); drop only on load ERROR.
      _clients[spot.id] = client;
      while (_clients.length > _clientCacheMax) {
        _clients.remove(_clients.keys.first);
      }
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
      // A transient failure (e.g. a flop-chunk timeout) must not throw away a
      // WARM cache-hit client's memoized manifest/chunks — re-insert it. A
      // never-loaded client stays out (drop on load error).
      if (cached != null) {
        _clients[spot.id] = cached;
      }
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
      // A turn DIFFERENT from the pinned one clears any pinned river (a
      // changed turn resets downstream); the auto-deal replay passes the
      // pinned card itself and keeps it.
      clearRiverPin: dealt == 0 && card != s.turnCard,
      clearError: true,
    );
    await _loadChunksForLine();
  }

  /// Re-pin a street's card (the card-box tap): replaces the pin and swaps
  /// any matching chance step IN PLACE — the betting line survives; only the
  /// chunks re-fetch. Valid at any cursor position.
  ///
  /// Changing the TURN to a different card CLEARS the pinned river and
  /// truncates the line at the river deal (the river street is un-dealt — its
  /// box returns to the empty "+" state): a changed turn resets downstream,
  /// and no surviving river pin means no suit-transposition ambiguity.
  /// Re-picking the identical turn keeps the river. Because the old river is
  /// cleared, it is a LEGAL new turn card (no collision guard against it).
  Future<void> setPinnedCard(
      {required bool river, required String card}) async {
    final m = state.manifest;
    if (m == null) return;
    if (m.flop.split(' ').contains(card)) return;
    if (river && card == state.turnCard) return;
    final turnChanged = !river && card != state.turnCard;
    var line = [...state.line];
    final chanceIdxs = [
      for (var i = 0; i < line.length; i++)
        if (line[i].startsWith('@')) i
    ];
    final pos = river ? 1 : 0;
    if (chanceIdxs.length > pos) line[chanceIdxs[pos]] = '@$card';
    if (turnChanged && chanceIdxs.length > 1) {
      // Drop the river chance step and everything after it.
      line = line.sublist(0, chanceIdxs[1]);
    }
    state = state.copyWith(
      line: line,
      cursor: state.cursor.clamp(0, line.length),
      turnCard: river ? null : card,
      riverCard: river ? card : null,
      clearRiverPin: turnChanged,
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
    // Value equality — lazy discovery can re-materialize the same spot as a
    // fresh ref object, which must still hit this memo.
    if (_rootOppFuture != null && _rootOppSpot == spot) {
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
