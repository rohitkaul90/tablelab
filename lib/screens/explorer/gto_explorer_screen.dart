// GTO Explorer ("Study") — Phase 1 MVP: browse the solved GTO library's spots
// visually. FLOP street only (turn/river = Phase 2); spots come from a local
// packs directory in dev (hosted packs = the Phase 1 hosting step).
// Design: launch/GTO_EXPLORER.md §4. Line-first navigation: the ribbon rewinds,
// the overview panel's action cards advance.
//
// Wrapped in AppTheme.dark like the other solver/felt screens — the action
// colors are dark-calibrated and it bounds the theming work.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../explorer/grid_aggregation.dart';
import '../../explorer/pack_codec.dart';
import '../../explorer/scenario_labels.dart';
import '../../providers/explorer_provider.dart';
import '../../theme/app_theme.dart';
import '../../equity/card.dart';
import '../../explorer/pack_source.dart';
import '../../explorer/preflop_ranges.dart';
import '../../explorer/root_equity.dart';
import '../../widgets/explorer/action_colors.dart';
import '../../widgets/explorer/board_picker_sheet.dart';
import '../../widgets/explorer/equity_chart.dart';
import '../../widgets/explorer/overview_panel.dart';
import '../../widgets/explorer/preflop_trail_view.dart';
import '../../widgets/explorer/strategy_grid.dart';
import '../../widgets/explorer/street_card_picker.dart';
import '../../widgets/app_drawer.dart';

class GtoExplorerScreen extends ConsumerStatefulWidget {
  final bool showScaffold;
  const GtoExplorerScreen({super.key, this.showScaffold = true});

  @override
  ConsumerState<GtoExplorerScreen> createState() => _GtoExplorerScreenState();
}

class _GtoExplorerScreenState extends ConsumerState<GtoExplorerScreen> {
  // Grid aggregation memoized on the node's identity: LayoutBuilder makes
  // _nodeView re-run on every resize/scroll rebuild, and recomputing the
  // O(combos×actions) aggregation each time also hands _GridPainter fresh
  // lists, defeating its shouldRepaint identity check (full 169-cell repaint
  // per frame). Same node object → same cached aggregates.
  PackNode? _aggNode;
  List<List<GridCellAgg?>>? _aggCells;
  NodeSummary? _aggSummary;
  GridLens _lens = GridLens.strategy;
  int _rightTab = 0; // 0 = Overview, 1 = Equity chart
  /// The preflop trail (who opened / responded / answered the 3-bet) shown in
  /// the unified strip. Synced to the loaded spot's scenario when a spot is
  /// opened directly.
  PreflopTrail _trail = const PreflopTrail();

  /// Whether the one-time initial trail sync (from the first-loaded spot) has
  /// happened — so it never re-fires and undoes a user's fold/reset of the
  /// opener. See _body.
  bool _trailInitSynced = false;

  /// Which PREFLOP decision the body inspects (0 open / 1 response / 2 vs
  /// 3-bet), or -1 when the body shows the postflop node at the cursor.
  int _preflopInspect = -1;
  String? _depthPref; // chosen stack-depth regime (settings gear); board picks use it
  int? _actionFilter; // grid shows only this action's share (right-pane cards)
  int? _chartHoverCombo; // chart crosshair → grid cell ring
  Set<int>? _gridHoverCombos; // grid cell hover → chart dots
  String? _selectedHand; // grid cell tapped → its combos in the Hands panel
  // (stored as the hand, e.g. 'A3s', so the selection survives node changes)

  /// Memoized on-device MC for the opponent's curve at a turn/river root (their
  /// reach-weighted range on this board) — keyed so it recomputes only on a
  /// real node change, not on every hover-driven rebuild.
  String? _oppEqKey;
  Future<List<PackCombo>>? _oppEqFuture;

  /// Horizontal scroll of the unified strip. The line can grow past the
  /// viewport (a deep all-in runout has many boxes), so we auto-scroll to keep
  /// the live decision visible and show edge chevrons when there is more.
  final ScrollController _stripCtrl = ScrollController();
  String? _lastStripScenario; // reset scroll to the left on a scenario change
  int _lastStripLineLen = 0; // chase the end only when the line GROWS
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _stripCtrl.addListener(_refreshStripArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(explorerProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    _stripCtrl.removeListener(_refreshStripArrows);
    _stripCtrl.dispose();
    super.dispose();
  }

  /// Recompute whether the strip can scroll either way; setState only when a
  /// flag flips (a couple of times per gesture, not per pixel).
  void _refreshStripArrows() {
    if (!_stripCtrl.hasClients ||
        !_stripCtrl.position.hasContentDimensions) {
      return;
    }
    final l = _stripCtrl.offset > 4;
    final r = _stripCtrl.offset < _stripCtrl.position.maxScrollExtent - 4;
    if (l != _canScrollLeft || r != _canScrollRight) {
      setState(() {
        _canScrollLeft = l;
        _canScrollRight = r;
      });
    }
  }

  /// Memoized per-node aggregates shared by the advance bar, grid, and
  /// overview (LayoutBuilder rebuilds must not recompute; the painter's
  /// identity-based shouldRepaint relies on stable lists). Node change also
  /// clears the action filter — indices are per-node.
  void _ensureAgg(ExplorerState state, PackNode node) {
    if (identical(_aggNode, node)) return;
    final manifest = state.manifest!;
    _aggNode = node;
    _aggCells = aggregateGrid(
      node,
      manifest.combosFor(oop: node.actorIsOop),
      board: [
        for (final c in [...manifest.flop.split(' '), ...state.dealtCards])
          parseCard(c),
      ],
    );
    _aggSummary = summarizeNode(node);
    _actionFilter = null;
    _chartHoverCombo = null; // combo ids are per node/actor
    _gridHoverCombos = null;
  }

  /// The aggregate cell for the currently selected hand at this node (null when
  /// nothing is selected or the hand has no live combos here). Selection is kept
  /// by HAND ('A3s') so it survives navigating to a different node.
  GridCellAgg? _selectedCellFor(List<List<GridCellAgg?>> cells) {
    final hand = _selectedHand;
    if (hand == null) return null;
    final (r, c) = handToCell(hand);
    if (r < 0 || r >= 13 || c < 0 || c >= 13) return null;
    return cells[r][c];
  }

  @override
  Widget build(BuildContext context) {
    // Keep the preflop strip in sync when a spot changes underneath it (the
    // init auto-select, or a board pick) — but never clobber a user-built
    // trail that already maps to the same scenario. ref.listen must live
    // DIRECTLY in build (not inside the Builder below — Riverpod asserts).
    ref.listen<ExplorerSpotRef?>(
        explorerProvider.select((s) => s.spot), (prev, next) {
      // Depth regimes differ per scenario, so a scenario switch drops any
      // remembered depth (the picker/settings then follow the loaded spot).
      if (prev?.scenario != next?.scenario) _depthPref = null;
      final sc = next?.scenario;
      if (sc != null && _trail.scenarioKey != sc) {
        setState(() => _trail = trailForScenario(sc));
      }
    });

    final body = Theme(
      data: AppTheme.dark,
      child: Builder(builder: (context) {
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: _body(context),
        );
      }),
    );
    if (!widget.showScaffold) return body;
    // Focus mode: drop the app bar (and the bottom nav, via MainNavigation) so
    // the spot gets the full window; float a small controls cluster instead.
    final maximized = ref.watch(studyMaximizedProvider);
    void setMax(bool v) =>
        ref.read(studyMaximizedProvider.notifier).state = v;
    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        appBar: maximized
            ? null
            : AppBar(
                // The hamburger opens the app drawer; the gear holds the
                // Cash/Tournament + stack-depth settings; fullscreen enters
                // focus mode.
                leading: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () =>
                      mainScaffoldKey.currentState?.openDrawer(),
                ),
                title: const Text('GTO Study'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen),
                    tooltip: 'Focus mode',
                    onPressed: () => setMax(true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Study settings',
                    onPressed: () => _openStudySettings(context),
                  ),
                ],
              ),
        body: maximized
            ? Stack(
                children: [
                  // Reserve a bottom band so the floating Exit controls never
                  // cover (or intercept taps on) the last content — the narrow
                  // ListView ends above the buttons instead of behind them.
                  Positioned.fill(
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 72),
                        child: body,
                      ),
                    ),
                  ),
                  // Bottom-right (free in focus mode) so it never obscures the
                  // strip; a solid, elevated, LABELLED Exit so it's obvious how
                  // to get back.
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: SafeArea(child: _focusControls(context, setMax)),
                  ),
                ],
              )
            : body,
      ),
    );
  }

  /// The floating controls shown in focus mode (settings + a clear Exit),
  /// since the app bar is hidden.
  Widget _focusControls(BuildContext context, void Function(bool) setMax) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: scheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Study settings',
            onPressed: () => _openStudySettings(context),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setMax(false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fullscreen_exit,
                      size: 20, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text('Exit',
                      style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The header gear: table-type (Cash/Tournament) and stack-depth (in bb)
  /// controls — the depth that used to sit next to each flop. Flips
  /// [PreflopTrail.trn] while KEEPING the built line; switches the loaded spot
  /// to the chosen depth on the same board.
  void _openStudySettings(BuildContext rootContext) {
    showModalBottomSheet<void>(
      context: rootContext,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        Widget label(String t) => Text(t,
            style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant, letterSpacing: 1.2));
        return SafeArea(
          child: StatefulBuilder(builder: (ctx, setSheet) {
            // The sheet route can outlive this screen; its rebuilds read the
            // screen's ref/fields, which throw on a defunct State.
            if (!mounted) return const SizedBox.shrink();
            final scenario = ref.read(explorerProvider).spot?.scenario ??
                _trail.scenarioKey;
            final depths = (scenario != null && !_trail.trn)
                ? kScenarioDepthStartBB[scenario]
                : null;
            final currentDepth =
                _depthPref ?? ref.read(explorerProvider).spot?.spr;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Study settings',
                      style: Theme.of(sheetContext).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  label('TABLE TYPE'),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Cash')),
                      ButtonSegment(value: true, label: Text('Tournament')),
                    ],
                    selected: {_trail.trn},
                    onSelectionChanged: (s) {
                      _setTrail(_trail.withTrnKeeping(s.first), inspect: -1);
                      setSheet(() {});
                    },
                  ),
                  if (depths != null) ...[
                    const SizedBox(height: 18),
                    label('STACK DEPTH'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 12)),
                      segments: [
                        for (final e in depths.entries)
                          ButtonSegment(
                              value: e.key,
                              label: Text(depthLabelBB(scenario!, e.key))),
                      ],
                      selected: {
                        if (currentDepth != null &&
                            depths.containsKey(currentDepth))
                          currentDepth
                        else
                          depths.keys.last
                      },
                      onSelectionChanged: (s) {
                        _setDepth(s.first);
                        setSheet(() {});
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    depths != null
                        ? 'Stack depth is approximate — packs are solved per '
                            'SPR bucket. Tournament mode uses ICM-aware preflop '
                            'ranges; solved postflop packs are cash-only.'
                        : 'Tournament mode uses ICM-aware preflop ranges. '
                            'Solved postflop packs are cash-only for now.',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  /// Switch the loaded spot to [regime] on the SAME board (the settings depth
  /// picker), and remember it so subsequent board picks use it. Only commits
  /// the preference when a pack actually exists for that board at that regime —
  /// otherwise the depth control would desync from the data still on screen.
  Future<void> _setDepth(String regime) async {
    if (!mounted) return; // reachable from sheet closures after disposal
    final spot = ref.read(explorerProvider).spot;
    if (spot == null) return;
    final notifier = ref.read(explorerProvider.notifier);
    // Normally already loaded (the spot came from this scenario's list), but
    // lazy discovery makes no such guarantee — ensure, then re-check.
    await notifier.ensureScenario(spot.scenario);
    if (!mounted) return;
    final st = ref.read(explorerProvider);
    if (st.spot != spot) return; // spot changed during the await
    final target = st
        .spotsFor(spot.scenario)
        .where((s) => s.flop == spot.flop && s.spr == regime)
        .toList();
    if (target.isEmpty) return; // no solved pack at that depth for this board
    setState(() {
      _depthPref = regime;
      _preflopInspect = -1;
    });
    if (target.first != spot) {
      notifier.selectSpot(target.first, userInitiated: true);
    }
  }

  Widget _body(BuildContext context) {
    final state = ref.watch(explorerProvider);
    final scheme = Theme.of(context).colorScheme;

    // Release-mode gap in the ref.listen sync: the auto-selected spot can be
    // fully loaded BEFORE this screen ever mounts (MainNavigation gates the
    // Study tab on catalog.isNotEmpty), so the change-only listener never fires
    // and the trail stays empty — dead navigation. Sync ONCE, lazily, when a
    // spot first becomes available. Must NOT fire every build: otherwise folding the
    // opener (which clears it) is instantly undone here, re-snapping the opener
    // back to the loaded spot's representative — you could never fold/change it.
    final spot0 = state.spot;
    if (!_trailInitSynced && spot0 != null) {
      _trailInitSynced = true;
      if (_trail.opener == null) {
        final synced = trailForScenario(spot0.scenario);
        if (synced.opener != null) _trail = synced;
      }
    }

    if (state.scanning) {
      return const Center(child: CircularProgressIndicator());
    }

    final preflopDecision =
        _preflopInspect >= 0 ? _trail.decision(_preflopInspect) : null;

    return Column(
      children: [
        // ONE unified line: preflop seats → flop → postflop decisions →
        // turn/river, GTO-Wizard-style (vertical action lists per box,
        // horizontal scroll).
        _unifiedStrip(context, state),
        const Divider(height: 1),
        Expanded(
          child: preflopDecision != null
              ? PreflopDecisionBody(
                  decision: preflopDecision,
                  subtitle: _preflopSubtitle(),
                )
              : _postflopContent(context, state),
        ),
        if (preflopDecision == null)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Beta · flop to river · solved to ≤0.5% exploitability on '
              'representative boards',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10.5),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  String _preflopSubtitle() => switch (_preflopInspect) {
        0 => 'opening range',
        1 => 'vs the ${_trail.opener} open',
        _ => 'vs the ${_trail.responder} 3-bet',
      };

  /// Apply a trail change: inspect the decision it creates, and re-target the
  /// postflop spot when the mapped scenario changed and packs exist for it
  /// (lazy: the scenario's index may need a fetch first).
  void _setTrail(PreflopTrail t, {int inspect = -1}) {
    if (!mounted) return; // reachable from sheet closures after disposal
    setState(() {
      _trail = t;
      _preflopInspect = inspect;
    });
    final sc = t.scenarioKey;
    if (sc == null) return;
    final st = ref.read(explorerProvider);
    if (st.spot?.scenario == sc) return;
    if (!st.scenarioKeys.contains(sc)) return; // no packs for this scenario
    _selectFirstSpotOf(sc, userInitiated: true);
  }

  /// Ensure [sc]'s index is loaded, then select its first spot — with
  /// post-await re-checks: the screen can unmount, the user can retarget the
  /// trail, or another selection can land during the fetch.
  Future<void> _selectFirstSpotOf(String sc,
      {required bool userInitiated}) async {
    final notifier = ref.read(explorerProvider.notifier);
    await notifier.ensureScenario(sc);
    if (!mounted) return;
    final st = ref.read(explorerProvider);
    if (st.spot?.scenario == sc) return; // already there
    if (_trail.scenarioKey != null && _trail.scenarioKey != sc) return;
    final candidates = st.spotsFor(sc);
    if (candidates.isNotEmpty) {
      notifier.selectSpot(candidates.first, userInitiated: userInitiated);
    }
  }

  /// The FLOP box tap: pick among the scenario's solved BOARDS (depth is chosen
  /// in the settings gear, so the picker no longer lists per-depth rows).
  /// [scenarioKey] overrides the trail's mapping (unknown-scenario packs).
  /// The sheet opens immediately and loads the scenario's index itself —
  /// lazy discovery means the board list may not be fetched yet.
  void _openBoardPicker(BuildContext context, ExplorerState state,
      {String? scenarioKey}) {
    final sc = scenarioKey ?? _trail.scenarioKey;
    if (sc == null || !state.scenarioKeys.contains(sc)) return;
    final notifier = ref.read(explorerProvider.notifier);
    // Load the picked board at the current depth preference (fall back to the
    // loaded spot's depth, then any depth that board has).
    final regime = _depthPref ?? state.spot?.spr;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => BoardPickerSheet(
        title: 'Solved boards — ${scenarioDisplayName(sc)}',
        selectedFlop: state.spot?.flop,
        preferredSpr: regime,
        // Captures the app-scoped notifier, not this State's ref — the sheet
        // is its own route and can outlive the screen.
        loadSpots: () => notifier.loadScenarioSpots(sc),
        onPick: (pick) {
          // The sheet is its own route and can outlive this screen
          // (conditional Study tab regated, auth swap) — a tap then
          // reaches a defunct State, where setState/ref throw.
          if (!mounted) return;
          setState(() => _preflopInspect = -1);
          notifier.selectSpot(pick, userInitiated: true);
        },
      ),
    );
  }

  /// Retry a failed scenario-index fetch, then (when nothing is loaded yet —
  /// the init auto-select path failed) select its first spot. NOT
  /// user-initiated: an error-screen Retry must not count as engagement.
  Future<void> _retryScenario(String sc) async {
    final notifier = ref.read(explorerProvider.notifier);
    await notifier.ensureScenario(sc);
    if (!mounted) return;
    final st = ref.read(explorerProvider);
    if (st.spot != null) return;
    final spots = st.spotsFor(sc);
    if (spots.isNotEmpty) notifier.selectSpot(spots.first);
  }

  Widget _postflopContent(BuildContext context, ExplorerState state) {
    if (state.catalog.isEmpty) {
      // The developer hint (local packs dir) must never reach prod users.
      const devHint = kDebugMode
          ? '\n\n(Developer: place packs under ~/tlpacks or pass '
              '--dart-define=TLPACKS_DIR=<dir>.)'
          : '';
      return _message(
        context,
        icon: Icons.school_outlined,
        title: 'No solved boards on this device yet',
        body: 'Preflop ranges work above — tap any seat\'s action. Postflop '
            'solution packs are being rolled out — check back soon.$devHint',
      );
    }
    // The catalog resolved but a scenario's board index failed to fetch
    // (transient network) — retryable, unlike the no-packs state above. Keyed
    // to the scenario the UI is actually trying to show: the trail's target,
    // or (before any spot ever loaded, e.g. init's first-scenario fetch
    // failing) whichever scenario errored.
    final wantedSc = _trail.scenarioKey ?? state.spot?.scenario;
    final failedSc = wantedSc != null && state.scenarioErrors.contains(wantedSc)
        ? wantedSc
        : (state.spot == null && state.scenarioErrors.isNotEmpty
            ? state.scenarioErrors.first
            : null);
    if (failedSc != null) {
      return _message(
        context,
        icon: Icons.cloud_off,
        title: 'Couldn\'t load the board list',
        body: 'The solved boards for '
            '${scenarioDisplayName(failedSc)} didn\'t load. '
            'Check your connection and retry.',
        action: TextButton(
          onPressed: () => _retryScenario(failedSc),
          child: const Text('Retry'),
        ),
      );
    }
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _message(
        context,
        icon: Icons.error_outline,
        title: 'Could not load this board',
        body: '${state.error}\n\nPick another board via the Flop box, or '
            'retry.',
        action: TextButton(
          onPressed: state.spot == null
              ? null
              : () =>
                  ref.read(explorerProvider.notifier).selectSpot(state.spot!),
          child: const Text('Retry'),
        ),
      );
    }
    if (state.manifest != null && state.flopNodes != null) {
      // The strip's line and the loaded spot can diverge (trail edited to an
      // unsolved/pack-less scenario, or Reset): rendering the OLD spot's
      // grid under the NEW line is silently wrong study data. Gate on match
      // (unknown future scenario keys pass — they have no trail to match).
      final spot = state.spot;
      if (spot != null &&
          trailForScenario(spot.scenario).opener != null &&
          _trail.scenarioKey != spot.scenario) {
        return _message(
          context,
          icon: Icons.sync_problem,
          title: 'Preflop line changed',
          body: 'The line above no longer matches the loaded board '
              '(${scenarioDisplayName(spot.scenario)}). Restore it, or '
              'complete the new line to a solved spot.',
          action: TextButton(
            onPressed: () => setState(() {
              _trail = trailForScenario(spot.scenario);
              _preflopInspect = -1;
            }),
            child: const Text('Restore the line for this board'),
          ),
        );
      }
      return _loaded(context, state);
    }
    return _message(context,
        icon: Icons.hourglass_empty,
        title: 'Pick a board',
        body: 'Complete the preflop action above, then tap the Flop box to '
            'choose a solved board.');
  }

  Widget _loaded(BuildContext context, ExplorerState state) {
    final node = state.currentNode;
    if (node != null) _ensureAgg(state, node);
    return node == null
        ? _streetClosed(context, state)
        : _nodeView(context, state, node);
  }

  // ── The UNIFIED line strip: preflop seats → flop → postflop → river ──────
  //
  // GTO-Wizard-style: every decision is a BOX with its available actions
  // listed VERTICALLY (chosen action filled), scrolling horizontally as the
  // hand advances. Preflop boxes come from the preset charts; the FLOP box
  // picks among the scenario's solved boards; postflop boxes are the pack
  // tree's nodes (tap an action = replay/edit via the line/cursor model).

  Widget _vRow(BuildContext context, String label, Color color,
      {bool highlighted = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Material(
        color: highlighted
            ? color.withValues(alpha: 0.55)
            : color.withValues(alpha: 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: highlighted
              ? BorderSide(color: color, width: 1.2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 62),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            child: Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                        highlighted ? FontWeight.w800 : FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  /// Compact bb formatter for the box chip ('82.5bb', '4bb', '100bb').
  String _fmtBB(double v) {
    final s = v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
    return '${s}bb';
  }

  Widget _vBox(BuildContext context,
      {required String header,
      required List<Widget> rows,
      VoidCallback? onHeaderTap,
      double? effStackBB, // effective stack shown next to the header
      bool inspected = false,
      bool dimmed = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Opacity(
        opacity: dimmed ? 0.5 : 1.0,
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: inspected
                ? BorderSide(
                    color: scheme.primary.withValues(alpha: 0.75), width: 1.4)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
            // IntrinsicWidth bounds the stretch: inside the horizontal
            // ListView the width constraint is INFINITE, and a bare
            // stretch-Column would demand it (RenderBox layout crash).
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onHeaderTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(header,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurfaceVariant)),
                        if (effStackBB != null) ...[
                          const SizedBox(width: 5),
                          Text(_fmtBB(effStackBB),
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary)),
                        ],
                      ],
                    ),
                  ),
                  ...rows,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The deep STARTING stack in bb the strip chains from. Prefer the loaded
  /// pack's exact flop effective stack (so preflop→flop→turn→river reads
  /// smoothly): start = flopEffective + each player's preflop investment. Falls
  /// back to the nominal depth-regime stack when no matching pack is loaded.
  double? _startEffBB(ExplorerState state) {
    final sc = _trail.scenarioKey;
    if (sc == null) return null;
    final invest = perPlayerPreflopInvestBB(sc);
    final m = state.manifest;
    if (m != null && m.scenario == sc && invest != null) {
      final bpu = bbPerUnit(sc, m.pot0);
      if (bpu != null) return m.effStack * bpu + invest;
    }
    final regime = _depthPref ?? state.spot?.spr;
    if (regime == null) return null;
    return kScenarioDepthStartBB[sc]?[regime]?.toDouble();
  }

  Widget _unifiedStrip(BuildContext context, ExplorerState state) {
    final scheme = Theme.of(context).colorScheme;
    final boxes = <Widget>[
      ..._preflopBoxes(context, _startEffBB(state)),
      _flopBox(context, state),
      ..._postflopBoxes(context, state),
      // Reset at the end of the scroll: rewind the recorded postflop line back
      // to preflop, keeping the trail + board (the Cash/Tournament toggle moved
      // to the header gear). Disabled when there's no postflop line to clear.
      Center(
        child: TextButton(
          onPressed: state.line.isEmpty
              ? null
              : () {
                  ref.read(explorerProvider.notifier).resetLine();
                  setState(() => _preflopInspect = 0);
                },
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 10.5)),
          child: const Text('Reset'),
        ),
      ),
    ];
    // Keep the live decision on screen as the line grows (e.g. a river all-in
    // pushes the next actor's box off the right edge).
    _maybeAutoScrollStrip(state);
    // Height must fit the TALLEST box (header + 3 action rows) with slack for
    // text scaling — a fixed-height horizontal list overflows loudly (21px
    // RenderFlex overflow at 104).
    return SizedBox(
      height: 128,
      child: Stack(
        children: [
          Container(
            height: 128,
            color: scheme.surfaceContainerLowest,
            child: ListView(
              controller: _stripCtrl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              children: [
                for (final b in boxes)
                  Align(alignment: Alignment.topLeft, child: b)
              ],
            ),
          ),
          _stripArrow(context, left: true),
          _stripArrow(context, left: false),
        ],
      ),
    );
  }

  /// After a strip content change: reset to the left on a new scenario, and
  /// chase the newest decision when the line GREW and the cursor is at its end
  /// (don't yank the view while inspecting an earlier box, or on a preflop-only
  /// load — the chevrons cover manual scrolling). Also refreshes the arrows so
  /// the right chevron appears on the very first overflowing layout.
  void _maybeAutoScrollStrip(ExplorerState state) {
    final scen = state.spot?.scenario;
    final len = state.line.length;
    final scenarioChanged = scen != _lastStripScenario;
    final grew = len > _lastStripLineLen;
    // Rewind to the LEFT only on a scenario switch or a full Reset (line
    // emptied). A partial edit-back (line shortens but isn't empty) leaves the
    // cursor on the edited box — don't yank it off-screen.
    final rewound = scenarioChanged || (len == 0 && _lastStripLineLen > 0);
    _lastStripScenario = scen;
    _lastStripLineLen = len;
    if (!scenarioChanged && !grew && !rewound) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stripCtrl.hasClients) return;
      if (rewound) {
        _stripCtrl.jumpTo(0);
      } else if (grew && state.atLineEnd) {
        final max = _stripCtrl.position.maxScrollExtent;
        if (max > _stripCtrl.offset + 4) {
          _stripCtrl.animateTo(max,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut);
        }
      }
      _refreshStripArrows();
    });
  }

  /// A tap-to-scroll chevron with a fade, shown only when the strip can scroll
  /// that way (there are more action boxes off that edge).
  Widget _stripArrow(BuildContext context, {required bool left}) {
    final scheme = Theme.of(context).colorScheme;
    final show = left ? _canScrollLeft : _canScrollRight;
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 36,
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  scheme.surfaceContainerLowest,
                  scheme.surfaceContainerLowest.withValues(alpha: 0),
                ],
              ),
            ),
            child: InkWell(
              onTap: () {
                if (!_stripCtrl.hasClients) return;
                final target = (left
                        ? _stripCtrl.offset - 220
                        : _stripCtrl.offset + 220)
                    .clamp(0.0, _stripCtrl.position.maxScrollExtent);
                _stripCtrl.animateTo(target,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut);
              },
              child: Icon(left ? Icons.chevron_left : Icons.chevron_right,
                  color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  /// Preflop seat boxes (from the preset charts), plus the opener's vs-3-bet
  /// box when a 3-bet happened. Any seat's action row is tappable: it rebuilds
  /// the trail from that point (a new opener voids the response, etc.).
  List<Widget> _preflopBoxes(BuildContext context, double? startEffBB) {
    final t = _trail;
    final openerIdx =
        t.opener == null ? -1 : kTrailPositions.indexOf(t.opener!);
    final out = <Widget>[];

    for (var i = 0; i < kTrailPositions.length; i++) {
      final pos = kTrailPositions[i];
      final rows = <Widget>[];
      var inspected = false;
      VoidCallback? headerTap;

      if (pos == t.opener) {
        inspected = _preflopInspect == 0;
        headerTap = () => setState(() => _preflopInspect = 0);
        rows.add(_vRow(context, 'Fold', kPreflopActionColors['Fold']!,
            onTap: () => _setTrail(t.reset(), inspect: -1)));
        rows.add(_vRow(context, 'Raise 2.5x', kPreflopActionColors['Raise']!,
            highlighted: true,
            onTap: () => setState(() => _preflopInspect = 0)));
      } else if (pos == t.responder) {
        inspected = _preflopInspect == 1;
        headerTap = () => setState(() => _preflopInspect = 1);
        rows.add(_vRow(context, 'Fold', kPreflopActionColors['Fold']!,
            onTap: () => _setTrail(t.withOpener(t.opener!), inspect: 0)));
        for (final a in ['Call', '3-bet']) {
          rows.add(_vRow(context, a, kPreflopActionColors[a]!,
              highlighted: t.responderAction == a,
              onTap: () => _setTrail(t.withResponse(pos, a), inspect: 1)));
        }
      } else if (openerIdx < 0) {
        // No opener yet: any seat but the BB can open first-in.
        if (pos == 'BB') {
          rows.add(_vRow(context, '—', Colors.grey));
        } else {
          rows.add(_vRow(context, 'Fold', kPreflopActionColors['Fold']!));
          rows.add(_vRow(context, 'Raise 2.5x', kPreflopActionColors['Raise']!,
              onTap: () => _setTrail(t.withOpener(pos), inspect: 0)));
        }
      } else if (i < openerIdx && pos != 'SB' && pos != 'BB') {
        // Folded before the open — Raise re-roots the trail here.
        rows.add(_vRow(context, 'Fold', kPreflopActionColors['Fold']!,
            highlighted: true));
        rows.add(_vRow(context, 'Raise 2.5x', kPreflopActionColors['Raise']!,
            onTap: () => _setTrail(t.withOpener(pos), inspect: 0)));
      } else {
        // A potential responder (after the opener, or a blind). Once another
        // seat responded, this one shows Fold — its Call/3-bet still swap the
        // responder role here.
        rows.add(_vRow(context, 'Fold', kPreflopActionColors['Fold']!,
            highlighted: t.responder != null));
        for (final a in ['Call', '3-bet']) {
          rows.add(_vRow(context, a, kPreflopActionColors[a]!,
              onTap: () => _setTrail(t.withResponse(pos, a), inspect: 1)));
        }
      }
      out.add(_vBox(context,
          header: pos,
          rows: rows,
          onHeaderTap: headerTap,
          effStackBB: startEffBB == null
              ? null
              : preflopEffStackBB(pos, startEffBB),
          inspected: inspected));
    }

    // The opener's answer to a 3-bet.
    if (t.responderAction == '3-bet' && t.opener != null) {
      out.add(_vBox(
        context,
        header: '${t.opener} (vs 3-bet)',
        inspected: _preflopInspect == 2,
        effStackBB: startEffBB == null
            ? null
            : preflopEffStackBBVs3Bet(startEffBB),
        onHeaderTap: () => setState(() => _preflopInspect = 2),
        rows: [
          for (final a in ['Fold', 'Call', '4-bet'])
            _vRow(context, a, kPreflopActionColors[a]!,
                highlighted: t.openerResponse == a,
                onTap: () => _setTrail(t.withOpenerResponse(a), inspect: 2)),
        ],
      ));
    }
    return out;
  }

  /// The FLOP box: the solved board for the trail's scenario (tap = pick a
  /// board/depth), or the reason there isn't one. A spot whose scenario key
  /// has NO trail mapping (future hosted packs, newer scenarios than this
  /// client) stays navigable generically — the trail model must not turn
  /// forward-compatible packs into a dead end (review finding).
  Widget _flopBox(BuildContext context, ExplorerState state) {
    final spot = state.spot;
    // The flop-root effective stack (bb) of the loaded pack — the same figure
    // the preflop chain lands on.
    final m = state.manifest;
    final bpu = m != null ? bbPerUnit(m.scenario, m.pot0) : null;
    final flopEffBB = (m != null && bpu != null) ? m.effStack * bpu : null;
    final spotUnknown =
        spot != null && trailForScenario(spot.scenario).opener == null;
    if (spotUnknown) {
      return _vBox(context, header: 'FLOP', effStackBB: flopEffBB, rows: [
        _vRow(context, '${spot.flop} · ${spot.spr}', const Color(0xFF7E57C2),
            highlighted: true,
            onTap: () =>
                _openBoardPicker(context, state, scenarioKey: spot.scenario)),
      ]);
    }
    final sc = _trail.scenarioKey;
    final matched = sc != null && spot != null && spot.scenario == sc;
    // O(1) against the catalog's key set — this runs per build, and the old
    // any() scan was O(spots) (26k at full density).
    final hasPacks = sc != null && state.scenarioKeys.contains(sc);

    final String detail;
    if (!_trail.closed) {
      detail = '—';
    } else if (sc == null) {
      detail = _trail.trn ? 'cash only' : 'not solved';
    } else if (!hasPacks) {
      detail = 'no packs';
    } else if (matched) {
      // Depth moved to the settings gear — show just the board for mapped
      // scenarios; unmapped (forward-compat) packs keep the raw regime.
      detail = kScenarioDepthStartBB.containsKey(spot.scenario)
          ? spot.flop
          : '${spot.flop} · ${spot.spr}';
    } else {
      detail = 'pick a board';
    }
    return _vBox(
      context,
      header: 'FLOP',
      inspected: false,
      dimmed: !hasPacks || !_trail.closed,
      // The flop effective stack, once a matched solved board is loaded.
      effStackBB: matched ? flopEffBB : null,
      rows: [
        _vRow(context, detail, const Color(0xFF7E57C2),
            highlighted: matched,
            onTap: hasPacks && _trail.closed
                ? () => _openBoardPicker(context, state)
                : null),
      ],
    );
  }

  /// Postflop decision boxes from the line/cursor model — one vertical box
  /// per decision (actions listed, taken one filled), card boxes for the
  /// runout, pending Turn/River placeholders, a Hand-over marker on folds.
  /// Only rendered when the loaded spot matches the trail's scenario.
  List<Widget> _postflopBoxes(BuildContext context, ExplorerState state) {
    final spot = state.spot;
    if (spot == null || state.manifest == null || state.flopNodes == null) {
      return const [];
    }
    // Known scenarios must match the trail (divergent line = hidden boxes);
    // UNKNOWN scenario keys render generically (forward compat).
    final known = trailForScenario(spot.scenario).opener != null;
    if (known && _trail.scenarioKey != spot.scenario) return const [];
    final scenario = state.manifest!.scenario;
    // bb per normalized pack unit — turns each node's pot into a running pot in
    // bb (null for a scenario with no bb anchor → the box shows no pot).
    final bpu = bbPerUnit(scenario, state.manifest!.pot0);
    final out = <Widget>[];

    // Bet/raise sizes render as % of pot; a shove reads 'All-in'. A CALL of
    // everything behind is flagged too so committed-depth lines aren't a
    // surprise when the runout has no nodes.
    String rowLabel(PackNode n, String action) {
      if (action.toUpperCase().startsWith('CALL')) {
        return n.toCall >= n.behind - 1e-6 ? 'Call · all-in' : 'Call';
      }
      return actionSizeLabel(action,
          potBefore: n.potBefore, toCall: n.toCall, behind: n.behind);
    }

    void decisionRows(List<Widget> rows, PackNode n, int stepIndex,
        {String? taken}) {
      final colors = actionColors(n.actions);
      for (var a = 0; a < n.actions.length; a++) {
        final action = n.actions[a];
        rows.add(_vRow(context, rowLabel(n, action), colors[a],
            highlighted: action == taken, onTap: () {
          setState(() => _preflopInspect = -1);
          final notifier = ref.read(explorerProvider.notifier);
          notifier.setCursor(stepIndex);
          notifier.advance(action);
        }));
      }
    }

    // Walk the line: decision boxes need the node at each prefix (for the
    // full action list); a missing chunk degrades to a single-action box.
    final prefix = <String>[];
    var dealtSoFar = 0;
    var idxInStreet = 0;
    for (var i = 0; i < state.line.length; i++) {
      final step = state.line[i];
      if (step.startsWith('@')) {
        dealtSoFar++;
        final river = dealtSoFar == 2;
        // Effective stack entering the new street = the behind of the first
        // node after the card (a chance node moves no chips).
        final nextNode = state.nodeAt([...prefix, step]);
        out.add(_vBox(
          context,
          header: river ? 'RIVER' : 'TURN',
          dimmed: i > state.cursor,
          effStackBB: (bpu != null && nextNode != null)
              ? nextNode.behind * bpu
              : null,
          rows: [
            _vRow(context, step.substring(1), const Color(0xFF7E57C2),
                highlighted: true,
                onTap: () => _openCardPicker(context, state, river: river)),
          ],
        ));
        prefix.add(step);
        idxInStreet = 0;
        continue;
      }
      final node = state.nodeAt(prefix);
      final actor = node != null
          ? seatLabel(scenario, isOop: node.actorIsOop)
          : seatLabel(scenario, isOop: idxInStreet.isEven);
      final rows = <Widget>[];
      final stepIndex = i;
      if (node != null) {
        decisionRows(rows, node, stepIndex, taken: step);
      } else {
        rows.add(_vRow(
            context, actionDisplayLabel(step), actionColors([step]).first,
            highlighted: true));
      }
      out.add(_vBox(
        context,
        header: actor,
        inspected: _preflopInspect < 0 && state.cursor == stepIndex,
        dimmed: i > state.cursor,
        effStackBB: (bpu != null && node != null) ? node.behind * bpu : null,
        onHeaderTap: () {
          setState(() => _preflopInspect = -1);
          ref.read(explorerProvider.notifier).setCursor(stepIndex);
        },
        rows: rows,
      ));
      prefix.add(step);
      idxInStreet++;
    }

    // The live decision at the line's end (nothing taken yet).
    final endNode = state.nodeAt(state.line);
    if (endNode != null) {
      final rows = <Widget>[];
      decisionRows(rows, endNode, state.line.length);
      out.add(_vBox(
        context,
        header: seatLabel(scenario, isOop: endNode.actorIsOop),
        inspected: _preflopInspect < 0 && state.atLineEnd,
        effStackBB: bpu != null ? endNode.behind * bpu : null,
        onHeaderTap: () {
          setState(() => _preflopInspect = -1);
          ref.read(explorerProvider.notifier).setCursor(state.line.length);
        },
        rows: rows,
      ));
    }

    // Pending runout boxes / hand-over marker. An ALL-IN closure ends the
    // decisions too — its placeholders would invite dead card picks.
    final lineDealt = dealtSoFar;
    final folded = state.line.isNotEmpty &&
        state.line.last.toUpperCase().startsWith('FOLD');
    final ended = folded || _lineIsAllIn(state);
    if (!ended) {
      if (lineDealt < 1) {
        out.add(_vBox(context, header: 'TURN', dimmed: true, rows: [
          _vRow(context, state.turnCard ?? '+', const Color(0xFF7E57C2),
              onTap: () => _openCardPicker(context, state, river: false)),
        ]));
      }
      if (lineDealt < 2) {
        out.add(_vBox(context, header: 'RIVER', dimmed: true, rows: [
          _vRow(context, state.riverCard ?? '+', const Color(0xFF7E57C2),
              onTap: () => _openCardPicker(context, state, river: true)),
        ]));
      }
    } else {
      out.add(_vBox(context, header: 'END', dimmed: true, rows: [
        _vRow(context, folded ? 'Hand over' : 'All-in', Colors.grey),
      ]));
    }
    return out;
  }

  void _openCardPicker(BuildContext context, ExplorerState state,
      {required bool river}) {
    final manifest = state.manifest;
    if (manifest == null) return;
    final excluded = <String>{
      ...manifest.flop.split(' '),
      // Exclude the OTHER street's pin so swaps can't collide.
      if (river && state.turnCard != null) state.turnCard!,
      if (!river && state.riverCard != null) state.riverCard!,
    };
    // Offer only the runouts the pack solved (suit-isomorphic representatives);
    // the merged twins have no node. River availability keys off the (stored)
    // turn card.
    final available = river
        ? (state.turnCard != null
            ? manifest.availableRiverCards(state.turnCard!)
            : null)
        : manifest.availableTurnCards();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
        child: StreetCardPicker(
          title: 'Pick the ${river ? 'river' : 'turn'} card',
          excluded: excluded,
          available: available,
          onPick: (c) {
            Navigator.of(sheetContext).pop();
            if (!mounted) return; // sheet route can outlive this screen
            ref
                .read(explorerProvider.notifier)
                .setPinnedCard(river: river, card: c);
          },
        ),
      ),
    );
  }

  Widget _nodeView(BuildContext context, ExplorerState state, PackNode node) {
    final manifest = state.manifest!;
    final combos = manifest.combosFor(oop: node.actorIsOop);
    _ensureAgg(state, node);
    final cells = _aggCells!;
    final summary = _aggSummary!;
    final colors = actionColors(node.actions);
    final actor =
        seatLabel(manifest.scenario, isOop: node.actorIsOop);

    // The grid must fit BOTH dimensions: it renders square, so on a wide
    // pane sizing by width alone overflows the viewport vertically (hit on
    // Windows: "bottom overflowed by 301 pixels"). Bound the square by the
    // smaller of width and (height minus the lens bar/legend chrome); in the
    // narrow layout the parent is a scrollable with unbounded height, where
    // width-sizing is correct.
    final grid = Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, c) {
        const chromeH = 46.0; // lens bar + spacing
        final legendH = _lens == GridLens.handClass ? 34.0 : 0.0;
        final side = !c.maxHeight.isFinite
            ? c.maxWidth
            : [c.maxWidth, c.maxHeight - chromeH - legendH]
                .reduce((a, b) => a < b ? a : b)
                .clamp(120.0, 4096.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _lensBar(context),
            const SizedBox(height: 6),
            Center(
              child: SizedBox(
                width: side,
                height: side,
                child: StrategyGrid(
                  cells: cells,
                  actionColors: colors,
                  lens: _lens,
                  filterAction: _actionFilter,
                  highlightCell: _chartHoverCombo != null &&
                          _chartHoverCombo! < combos.length
                      ? comboCell(combos[_chartHoverCombo!])
                      : null,
                  // Hover drives the Hands panel: the hovered hand's combos
                  // populate the boxes (sticky — the last hand stays shown when
                  // the mouse leaves the grid, so it doesn't flicker to empty).
                  onCellHover: (cell) {
                    final agg =
                        cell == null ? null : cells[cell.$1][cell.$2];
                    final ids = agg?.combos.map((c) => c.comboId).toSet();
                    final hand = agg?.hand;
                    final handChanged = hand != null && hand != _selectedHand;
                    if (setEquals(ids, _gridHoverCombos) && !handChanged) {
                      return;
                    }
                    setState(() {
                      _gridHoverCombos = ids;
                      if (hand != null) _selectedHand = hand;
                    });
                  },
                  // Tap also selects (touch, where there is no hover) and shows
                  // the Overview so the Hands panel is visible.
                  onCellTap: (cell) => setState(() {
                    _selectedHand = cell.hand;
                    _rightTab = 0;
                  }),
                ),
              ),
            ),
            if (_lens == GridLens.handClass) _classLegend(context),
          ],
        );
      }),
    );
    final tabToggle = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 11.5),
        ),
        segments: const [
          ButtonSegment(value: 0, label: Text('Overview')),
          ButtonSegment(value: 1, label: Text('Equity chart')),
        ],
        selected: {_rightTab},
        onSelectionChanged: (s) => setState(() => _rightTab = s.first),
      ),
    );

    // Build the (potentially expensive) equity header ONCE here, above the
    // LayoutBuilder — _equityPane calls equityCurve(node.combos), and building it
    // inside the builder would recompute it on every constraint-driven rebuild
    // (rotation/keyboard/resize). See the CLAUDE.md right-pane note.
    final headerChart =
        _rightTab == 1 ? _equityPane(context, state, node) : null;

    // Both tabs render the Overview; the Equity-chart tab swaps the stat box for
    // the equity chart above the actions. [embedded] controls who owns the
    // scroll (the wide pane scrolls itself; the narrow single-column doesn't).
    OverviewPanel overview({required bool embedded}) => OverviewPanel(
          node: node,
          summary: summary,
          actorLabel: actor,
          selectedAction: _actionFilter,
          bbPerUnit: bbPerUnit(manifest.scenario, manifest.pot0),
          comboNames: combos,
          selectedCell: _selectedCellFor(cells),
          headerChart: headerChart,
          embedded: embedded,
          onActionTap: (a) => setState(
              () => _actionFilter = _actionFilter == a ? null : a),
        );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 11, child: grid),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [tabToggle, Expanded(child: overview(embedded: false))],
              ),
            ),
          ],
        );
      }
      // Narrow: ONE outer scroll — the grid, the tab toggle, then the embedded
      // (non-scrolling) Overview. Nesting the Overview's own ListView inside
      // this one trapped the scroll gesture and stuck the user at the bottom.
      return ListView(
        children: [
          grid,
          tabToggle,
          overview(embedded: true),
        ],
      );
    });
  }

  /// Cumulative equity distributions at the current game state — BOTH players,
  /// always: the acting player's curve from THIS node; the opponent's from
  /// their most recent node on the line (whose equities were computed vs
  /// exactly the range the actor holds entering this node). At the flop root
  /// the opponent has never acted, so their curve is Monte-Carlo'd on-device
  /// once per spot (cached in the notifier) and labeled as estimated.
  Widget _equityPane(
      BuildContext context, ExplorerState state, PackNode node) {
    final manifest = state.manifest!;
    final scenario = manifest.scenario;
    final actorLabel = seatLabel(scenario, isOop: node.actorIsOop);
    final oppLabel = seatLabel(scenario, isOop: !node.actorIsOop);
    final actorNames = manifest.combosFor(oop: node.actorIsOop);
    final oppNames = manifest.combosFor(oop: !node.actorIsOop);
    final actorSeries = EquityCurveSeries(
      '$actorLabel (to act)',
      const Color(0xFF66BB6A),
      equityCurve(node.combos),
      actorNames,
    );

    // Fixed height — the chart now sits inside the Overview's scroll (above the
    // actions), not a full pane, so it can't use Expanded.
    Widget chart(List<EquityCurveSeries> series, {String? note}) {
      if (series.every((s) => s.points.isEmpty)) {
        return Text('No per-combo equity at this node.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: EquityChart(
              series: series,
              highlightCombos: _gridHoverCombos,
              onHoverCombo: (id) {
                if (id == _chartHoverCombo) return;
                setState(() => _chartHoverCombo = id);
              },
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note,
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
        ],
      );
    }

    // The opponent's curve must describe the range the actor actually FACES:
    // their last node's ENTERING reach narrowed by the action they took, and
    // only when that node is on the SAME street (its stored equities are for
    // its own board — a flop node's equity under a turn actor's curve told a
    // wrong advantage story; review finding).
    final opp = _opponentLast(state, node);
    final cursorDealt = state.dealtCards.length;
    if (opp != null && opp.dealt == cursorDealt) {
      return chart([
        actorSeries,
        EquityCurveSeries(
          oppLabel,
          const Color(0xFF64B5F6),
          equityCurve(_narrowedByAction(opp.node, opp.taken)),
          oppNames,
        ),
      ]);
    }
    if (cursorDealt > 0) {
      // A turn/river ROOT: the opponent hasn't acted on THIS street, so they
      // have no same-board STORED equity. Unlike the flop root their range is
      // reach-skewed by earlier betting, so we Monte-Carlo it WEIGHTED by reach
      // (their entering range narrowed by their last action) on this board.
      if (opp == null) {
        return chart([actorSeries],
            note: '$oppLabel has not acted on this street yet.');
      }
      final board = [
        for (final c in [...manifest.flop.split(' '), ...state.dealtCards])
          parseCard(c)
      ];
      final oppRange = _narrowedByAction(opp.node, opp.taken);
      final key = '${manifest.flop}|${state.dealtCards.join('/')}|'
          '${opp.node.path}|${opp.taken}|${node.path}';
      if (key != _oppEqKey) {
        _oppEqKey = key;
        _oppEqFuture = compute(
          computeOppRangeEquities,
          OppRangeEquityPayload(
            hero: [
              for (final c in oppRange)
                if (c.comboId < oppNames.length)
                  WeightedCombo(c.comboId, oppNames[c.comboId], c.reach),
            ],
            villain: [
              for (final c in node.combos)
                if (c.comboId < actorNames.length)
                  WeightedCombo(c.comboId, actorNames[c.comboId], c.reach),
            ],
            board: board,
          ),
        );
      }
      return FutureBuilder<List<PackCombo>>(
        future: _oppEqFuture,
        builder: (context, snap) {
          final oppEq = snap.data;
          return chart(
            [
              actorSeries,
              if (oppEq != null && oppEq.isNotEmpty)
                EquityCurveSeries(
                  '$oppLabel (est.)',
                  const Color(0xFF64B5F6),
                  equityCurve(oppEq),
                  oppNames,
                ),
            ],
            note: oppEq == null
                ? 'computing $oppLabel equity…'
                : '$oppLabel curve estimated on-device (reach-weighted range, '
                    'this board)',
          );
        },
      );
    }
    // Flop root: the opponent's curve is computed on-device (once per spot).
    return FutureBuilder<List<PackCombo>>(
      future: ref.read(explorerProvider.notifier).rootOpponentEquities(),
      builder: (context, snap) {
        final opp = snap.data;
        return chart(
          [
            actorSeries,
            if (opp != null && opp.isNotEmpty)
              EquityCurveSeries(
                '$oppLabel (est.)',
                const Color(0xFF64B5F6),
                equityCurve(opp),
                oppNames,
              ),
          ],
          note: opp == null
              ? 'computing $oppLabel equity…'
              : '$oppLabel curve estimated on-device (full ranges, this board)',
        );
      },
    );
  }

  /// Did the line's LAST action put the stacks in (bet/raise for everything
  /// behind, or a call of one)? Uses the pack's per-node chip state.
  bool _lineIsAllIn(ExplorerState state) {
    for (var i = state.line.length - 1; i >= 0; i--) {
      final step = state.line[i];
      if (step.startsWith('@')) continue;
      final n = state.nodeAt(state.line.sublist(0, i));
      if (n == null) return false;
      final u = step.toUpperCase();
      if (u.startsWith('ALLIN')) return true;
      if (u.startsWith('CALL')) return n.toCall >= n.behind - 1e-6;
      if (u.startsWith('BET') || u.startsWith('RAISE')) {
        final amt = double.tryParse(
            RegExp(r'[0-9.]+').firstMatch(u)?.group(0) ?? '');
        return amt != null && amt >= n.behind - 1e-6;
      }
      return false;
    }
    return false;
  }

  /// The opponent's most recent decision BEFORE the cursor: their node, the
  /// action they TOOK there (the next line step), and how many cards were
  /// dealt at that node (its street). Null when they haven't acted yet.
  ({PackNode node, String taken, int dealt})? _opponentLast(
      ExplorerState state, PackNode node) {
    final prefix = state.prefix;
    for (var i = prefix.length - 1; i >= 0; i--) {
      if (prefix[i].startsWith('@')) continue;
      final n = state.nodeAt(prefix.sublist(0, i));
      if (n != null && n.actorIsOop != node.actorIsOop) {
        var dealt = 0;
        for (var k = 0; k < i; k++) {
          if (prefix[k].startsWith('@')) dealt++;
        }
        return (node: n, taken: prefix[i], dealt: dealt);
      }
    }
    return null;
  }

  /// The opponent's range AFTER the action they took: entering reach × that
  /// action's per-combo frequency. Their node's stored equity is valid on the
  /// node's own street — the caller only uses this same-street.
  List<PackCombo> _narrowedByAction(PackNode oppNode, String taken) {
    final ai = oppNode.actions.indexOf(taken);
    if (ai < 0) return oppNode.combos;
    return [
      for (final c in oppNode.combos)
        if (ai < c.freqs.length && c.reach * c.freqs[ai] > 1e-6)
          PackCombo(
            comboId: c.comboId,
            reach: c.reach * c.freqs[ai],
            equity: c.equity,
            evPassive: c.evPassive,
            freqs: c.freqs,
            evs: c.evs,
          ),
    ];
  }

  /// The cursor points at no node. Mid-line that only means a missing chunk
  /// (the line itself is intact); at the line's END decide the state: fold
  /// ends the hand; an all-in call runs out; a closed flop/turn auto-deals
  /// the pinned card or offers the picker; a closed river is showdown.
  Widget _streetClosed(BuildContext context, ExplorerState state) {
    if (state.chunkLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // stepBack normalizes BACKWARD over chance steps — setCursor(cursor-1)
    // normalizes forward and was a no-op right after a dealt card.
    Widget back() => TextButton(
          onPressed: () => ref.read(explorerProvider.notifier).stepBack(),
          child: const Text('Back one step'),
        );
    if (state.line.isEmpty) {
      return _message(context,
          icon: Icons.error_outline,
          title: 'Spot has no root decision',
          body: 'This pack looks malformed — pick another spot above.');
    }
    if (!state.atLineEnd) {
      // Inspecting mid-line but the street's chunk is missing (thin runout).
      return _message(context,
          icon: Icons.casino_outlined,
          title: 'This street is unavailable',
          body: 'The pack does not carry this runout. Change the '
              '${state.dealtCards.length <= 1 ? 'turn' : 'river'} card via '
              'its box above, or tap an earlier action.',
          action: back());
    }
    final last = state.line.last.toUpperCase();
    if (last.startsWith('FOLD')) {
      return _message(context,
          icon: Icons.close,
          title: 'Hand over — fold',
          body: 'This line ends the hand. Tap any earlier box above to '
              'review a decision — the line stays as played.',
          action: back());
    }
    if (last.startsWith('@')) {
      // A card was dealt but its line has no node. Distinguish the ALL-IN
      // line (stacks are in — the pack is fine, there are just no more
      // decisions) from a runout chunk the pack doesn't carry.
      if (_lineIsAllIn(state)) {
        return _message(context,
            icon: Icons.paid_outlined,
            title: 'All-in — runout to showdown',
            body: 'The stacks went in on an earlier street; there are no '
                'further decisions on this line. Tap any earlier box above '
                'to review a decision.',
            action: back());
      }
      return _message(context,
          icon: Icons.casino_outlined,
          title: 'No decisions on this runout',
          body: 'The pack does not carry this runout — change the card via '
              'its box above, or tap an earlier action.',
          action: back());
    }
    // Street closed by matched action. All-in call → showdown, no more cards
    // to pick meaningfully street by street. _lineIsAllIn covers BOTH the
    // literal ALLIN label and a full-stack BET called (packs express most
    // shoves as 'BET <everything behind>' — the literal check alone walked
    // users into a dead card pick; review finding).
    final dealt = state.dealtCards.length;
    if (_lineIsAllIn(state)) {
      return _message(context,
          icon: Icons.paid_outlined,
          title: 'All-in — runout to showdown',
          body: 'The stacks are in; there are no further decisions. Tap any '
              'earlier box above to review a decision.',
          action: back());
    }
    if (dealt >= 2) {
      return _message(context,
          icon: Icons.flag_outlined,
          title: 'Showdown',
          body: 'River action complete — the hand goes to showdown. Tap any '
              'earlier box above to review a decision; the line stays as '
              'played.',
          action: back());
    }
    // A pinned card for the next street AUTO-DEALS (the user never re-enters
    // a card after a rewind; the strip's card boxes change pins explicitly).
    final pinned = dealt == 0 ? state.turnCard : state.riverCard;
    if (pinned != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final s = ref.read(explorerProvider);
        if (!identical(s, state) || s.chunkLoading) return;
        ref.read(explorerProvider.notifier).pickCard(pinned);
      });
      return const Center(child: CircularProgressIndicator());
    }
    // No pin yet: offer the next street's card inline.
    final excluded = <String>{
      ...?state.manifest?.flop.split(' '),
      ...state.dealtCards,
      if (dealt == 0 && state.riverCard != null) state.riverCard!,
    };
    // Offer only solved runouts (see _openCardPicker).
    final available = dealt == 0
        ? state.manifest?.availableTurnCards()
        : (state.turnCard != null
            ? state.manifest?.availableRiverCards(state.turnCard!)
            : null);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreetCardPicker(
              title: dealt == 0 ? 'Pick the turn card' : 'Pick the river card',
              excluded: excluded,
              available: available,
              onPick: (c) =>
                  ref.read(explorerProvider.notifier).pickCard(c),
            ),
            const SizedBox(height: 4),
            back(),
          ],
        ),
      ),
    );
  }

  /// Lens toggle above the grid: strategy (action mix) vs hand class (the
  /// same DCE classes the AI coaching quotes).
  Widget _lensBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SegmentedButton<GridLens>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 11.5),
          ),
          segments: const [
            ButtonSegment(value: GridLens.strategy, label: Text('Strategy')),
            ButtonSegment(value: GridLens.handClass, label: Text('Hand class')),
          ],
          selected: {_lens},
          onSelectionChanged: (s) => setState(() => _lens = s.first),
        ),
      ],
    );
  }

  Widget _classLegend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final e in kHandClassColors.entries)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: e.value, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(handClassShortLabel(e.key),
                  style:
                      TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
            ]),
        ],
      ),
    );
  }

  Widget _message(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ),
    );
  }
}
