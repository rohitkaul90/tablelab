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
import '../../widgets/explorer/action_colors.dart';
import '../../widgets/explorer/combo_detail_sheet.dart';
import '../../widgets/explorer/equity_chart.dart';
import '../../widgets/explorer/overview_panel.dart';
import '../../widgets/explorer/preflop_trail_view.dart';
import '../../widgets/explorer/strategy_grid.dart';
import '../../widgets/explorer/street_card_picker.dart';

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
  bool _preflopMode = false; // Preflop trail vs the postflop pack explorer
  int? _actionFilter; // grid shows only this action's share (right-pane cards)
  int? _chartHoverCombo; // chart crosshair → grid cell ring
  Set<int>? _gridHoverCombos; // grid cell hover → chart dots

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(explorerProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
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
    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        appBar: AppBar(title: const Text('GTO Study')),
        body: body,
      ),
    );
  }

  Widget _body(BuildContext context) {
    final state = ref.watch(explorerProvider);

    if (state.scanning) {
      return const Center(child: CircularProgressIndicator());
    }
    // Preflop study works from the BUNDLED preset charts — no packs needed —
    // so the mode toggle sits above the pack-dependent postflop body.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            segments: const [
              ButtonSegment(value: true, label: Text('Preflop')),
              ButtonSegment(value: false, label: Text('Postflop')),
            ],
            selected: {_preflopMode},
            onSelectionChanged: (s) =>
                setState(() => _preflopMode = s.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _preflopMode
              ? PreflopTrailView(
                  availableScenarios: {
                    for (final s in state.spots) s.scenario
                  },
                  onStudyPostflop: _studyPostflop,
                )
              : _postflopBody(context, state),
        ),
      ],
    );
  }

  /// Preflop → postflop handoff: switch modes and open a spot of the matched
  /// scenario (keeping the current spot when it already matches).
  void _studyPostflop(String scenarioKey) {
    final state = ref.read(explorerProvider);
    final candidates =
        state.spots.where((s) => s.scenario == scenarioKey).toList();
    if (candidates.isEmpty) return;
    setState(() => _preflopMode = false);
    if (state.spot?.scenario != scenarioKey) {
      ref.read(explorerProvider.notifier).selectSpot(candidates.first);
    }
  }

  Widget _postflopBody(BuildContext context, ExplorerState state) {
    final scheme = Theme.of(context).colorScheme;
    if (state.spots.isEmpty) {
      // The developer hint (local packs dir) must never reach prod users.
      const devHint = kDebugMode
          ? '\n\n(Developer: place packs under ~/tlpacks or pass '
              '--dart-define=TLPACKS_DIR=<dir>.)'
          : '';
      return _message(
        context,
        icon: Icons.school_outlined,
        title: 'No solved spots available yet',
        body: 'GTO Study browses solver solutions of common preflop '
            'scenarios. Solution packs are being rolled out — check back '
            'soon.$devHint',
      );
    }

    // The spot-picker header stays visible in EVERY state below — an error on
    // one spot must not hide the only control that can select another (a
    // corrupt pack would otherwise brick the whole tab; there is no other
    // path that clears ExplorerState.error).
    return Column(
      children: [
        _spotHeader(context, state),
        const Divider(height: 1),
        if (state.loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (state.error != null)
          Expanded(
            child: _message(
              context,
              icon: Icons.error_outline,
              title: 'Could not load this spot',
              body: '${state.error}\n\nPick another spot above, or retry.',
              action: TextButton(
                onPressed: state.spot == null
                    ? null
                    : () => ref
                        .read(explorerProvider.notifier)
                        .selectSpot(state.spot!),
                child: const Text('Retry'),
              ),
            ),
          )
        else if (state.manifest != null && state.flopNodes != null)
          Expanded(child: _loaded(context, state))
        else
          Expanded(
            child: _message(context,
                icon: Icons.hourglass_empty,
                title: 'Select a spot',
                body: 'Pick a flop + stack depth above.'),
          ),
        // Beta footer — honest scope framing (26 solved flops per depth).
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

  Widget _spotHeader(BuildContext context, ExplorerState state) {
    final scenarios =
        state.spots.map((s) => s.scenario).toSet().toList()..sort();
    final scenario = state.spot?.scenario ?? scenarios.first;
    final inScenario =
        state.spots.where((s) => s.scenario == scenario).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (scenarios.length > 1) ...[
            Expanded(
              flex: 5,
              child: _dropdown<String>(
                context,
                value: scenario,
                items: [
                  for (final sc in scenarios)
                    DropdownMenuItem(
                        value: sc, child: Text(scenarioDisplayName(sc))),
                ],
                onChanged: (sc) {
                  final first = state.spots.firstWhere(
                      (s) => s.scenario == sc,
                      orElse: () => state.spots.first);
                  ref.read(explorerProvider.notifier).selectSpot(first);
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 4,
            child: _dropdown(
              context,
              value: state.spot,
              items: [
                for (final s in inScenario)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) {
                if (s != null) {
                  ref.read(explorerProvider.notifier).selectSpot(s);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(),
      ),
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _loaded(BuildContext context, ExplorerState state) {
    final node = state.currentNode;
    if (node != null) _ensureAgg(state, node);

    return Column(
      children: [
        // The LINE STRIP: the whole hand as boxes — played actions (tap =
        // rewind), pinned Turn/River card boxes (tap = pick/change the card;
        // pins survive rewinds so cards are never re-entered), and the
        // current decision's action buttons (NO frequencies — the strip
        // reflects what the user plays; consequences live in the right pane).
        _lineStrip(context, state, node),
        const SizedBox(height: 4),
        Expanded(
          child: node == null
              ? _streetClosed(context, state)
              : _nodeView(context, state, node),
        ),
      ],
    );
  }

  Widget _lineStrip(BuildContext context, ExplorerState state, PackNode? node) {
    final scheme = Theme.of(context).colorScheme;
    final manifest = state.manifest!;
    final scenario = manifest.scenario;
    final boxes = <Widget>[];

    Widget box({
      required String label,
      Color? color,
      Color? borderColor,
      VoidCallback? onTap,
      Widget? child,
      bool dimmed = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Opacity(
          opacity: dimmed ? 0.45 : 1.0,
          child: Material(
            color: color ?? scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: borderColor != null
                  ? BorderSide(color: borderColor, width: 1.2)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: child ??
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      );
    }

    // One recorded step as a box. Action boxes SET THE CURSOR (inspect that
    // decision — the line is never reset); card boxes open the picker (change
    // the runout in place).
    Widget stepBox(int i, String step,
        {required int idxInStreet,
        required int dealtSoFar,
        required bool dimmed}) {
      if (step.startsWith('@')) {
        final river = dealtSoFar == 2;
        return box(
          label: '${river ? 'River' : 'Turn'} ${step.substring(1)}',
          color: scheme.tertiaryContainer.withValues(alpha: 0.5),
          dimmed: dimmed,
          onTap: () => _openCardPicker(context, state, river: river),
        );
      }
      final actor = seatLabel(scenario, isOop: idxInStreet.isEven);
      return box(
        label: '$actor ${actionDisplayLabel(step)}',
        color: actionColors([step]).first.withValues(alpha: 0.30),
        dimmed: dimmed,
        onTap: () => ref.read(explorerProvider.notifier).setCursor(i),
      );
    }

    // The decision box at the cursor: all available actions as buttons; the
    // RECORDED next action (replaying a line) is outlined — tapping it
    // replays, tapping another EDITS the line (the still-valid tail regrows).
    Widget decisionBox(PackNode n) {
      final actor = seatLabel(scenario, isOop: n.actorIsOop);
      final colors = actionColors(n.actions);
      final recorded = state.recordedNext;
      return box(
        label: '',
        color: scheme.surfaceContainerHigh,
        borderColor: scheme.primary.withValues(alpha: 0.6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$actor:',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(width: 6),
            for (var a = 0; a < n.actions.length; a++) ...[
              Material(
                color: colors[a]
                    .withValues(alpha: n.actions[a] == recorded ? 0.55 : 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: n.actions[a] == recorded
                      ? BorderSide(color: colors[a], width: 1.4)
                      : BorderSide.none,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => ref
                      .read(explorerProvider.notifier)
                      .advance(n.actions[a]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    child: Text(actionDisplayLabel(n.actions[a]),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              if (a < n.actions.length - 1) const SizedBox(width: 5),
            ],
          ],
        ),
      );
    }

    // Flop box (tap = view the root decision).
    boxes.add(box(
      label: 'Flop ${manifest.flop}',
      onTap: state.cursor == 0
          ? null
          : () => ref.read(explorerProvider.notifier).setCursor(0),
    ));

    // Recorded steps with the decision box inserted at the cursor. The
    // recorded step AT the cursor is represented by the outlined button in
    // the decision box (not duplicated as its own box).
    var idxInStreet = 0;
    var dealtSoFar = 0;
    for (var i = 0; i < state.line.length; i++) {
      final step = state.line[i];
      final isChance = step.startsWith('@');
      if (isChance) dealtSoFar++;
      if (i == state.cursor && node != null) boxes.add(decisionBox(node));
      if (!(i == state.cursor && !isChance)) {
        boxes.add(stepBox(i, step,
            idxInStreet: idxInStreet,
            dealtSoFar: dealtSoFar,
            dimmed: i >= state.cursor));
      }
      idxInStreet = isChance ? 0 : idxInStreet + 1;
    }
    if (state.atLineEnd && node != null) boxes.add(decisionBox(node));

    // Future chance boxes out to the river (only when the line doesn't
    // already contain them): pinned card or '+'. Fold ends with a marker.
    final lineDealt = [
      for (final s in state.line)
        if (s.startsWith('@')) s
    ].length;
    final ended = state.line.isNotEmpty &&
        state.line.last.toUpperCase().startsWith('FOLD');
    if (!ended) {
      if (lineDealt < 1) {
        boxes.add(box(
          label: 'Turn ${state.turnCard ?? '+'}',
          color: scheme.tertiaryContainer.withValues(alpha: 0.22),
          onTap: () => _openCardPicker(context, state, river: false),
        ));
      }
      if (lineDealt < 2) {
        boxes.add(box(
          label: 'River ${state.riverCard ?? '+'}',
          color: scheme.tertiaryContainer.withValues(alpha: 0.22),
          onTap: () => _openCardPicker(context, state, river: true),
        ));
      }
    } else {
      boxes.add(box(
          label: 'Hand over',
          color: scheme.surfaceContainerLow,
          dimmed: !state.atLineEnd,
          onTap: null));
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        children: [for (final b in boxes) Center(child: b)],
      ),
    );
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
        child: StreetCardPicker(
          title: 'Pick the ${river ? 'river' : 'turn'} card',
          excluded: excluded,
          onPick: (c) {
            Navigator.of(sheetContext).pop();
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
                  onCellHover: (cell) {
                    final ids = cell == null
                        ? null
                        : cells[cell.$1][cell.$2]
                            ?.combos
                            .map((c) => c.comboId)
                            .toSet();
                    if (setEquals(ids, _gridHoverCombos)) return;
                    setState(() => _gridHoverCombos = ids);
                  },
                  onCellTap: (cell) => showComboDetailSheet(context,
                      cell: cell, node: node, comboNames: combos),
                ),
              ),
            ),
            if (_lens == GridLens.handClass) _classLegend(context),
          ],
        );
      }),
    );
    final rightPane = Column(
      children: [
        Padding(
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
        ),
        Expanded(
          child: _rightTab == 0
              ? OverviewPanel(
                  node: node,
                  summary: summary,
                  actorLabel: actor,
                  selectedAction: _actionFilter,
                  onActionTap: (a) => setState(
                      () => _actionFilter = _actionFilter == a ? null : a),
                )
              : _equityPane(context, state, node),
        ),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 11, child: grid),
            const VerticalDivider(width: 1),
            Expanded(flex: 9, child: rightPane),
          ],
        );
      }
      return ListView(
        children: [
          grid,
          SizedBox(height: 420, child: rightPane),
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

    Widget chart(List<EquityCurveSeries> series, {String? note}) {
      if (series.every((s) => s.points.isEmpty)) {
        return _message(context,
            icon: Icons.show_chart,
            title: 'No equity data at this node',
            body: 'This pack carries no per-combo equity here.');
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
              Text(note,
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final oppNode = _opponentNode(state, node);
    if (oppNode != null) {
      return chart([
        actorSeries,
        EquityCurveSeries(
          oppLabel,
          const Color(0xFF64B5F6),
          equityCurve(oppNode.combos),
          oppNames,
        ),
      ]);
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

  /// The opponent's most recent action node BEFORE the cursor (searching
  /// prefixes longest-first across the loaded street chunks), or null when
  /// they haven't acted yet (e.g. the flop root).
  PackNode? _opponentNode(ExplorerState state, PackNode node) {
    final prefix = state.prefix;
    for (var i = prefix.length - 1; i >= 0; i--) {
      final n = state.nodeAt(prefix.sublist(0, i));
      if (n != null && n.actorIsOop != node.actorIsOop) return n;
    }
    return null;
  }

  /// The cursor points at no node. Mid-line that only means a missing chunk
  /// (the line itself is intact); at the line's END decide the state: fold
  /// ends the hand; an all-in call runs out; a closed flop/turn auto-deals
  /// the pinned card or offers the picker; a closed river is showdown.
  Widget _streetClosed(BuildContext context, ExplorerState state) {
    if (state.chunkLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    Widget back() => TextButton(
          onPressed: () => ref
              .read(explorerProvider.notifier)
              .setCursor(state.cursor > 0 ? state.cursor - 1 : 0),
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
      // A card was dealt but its line has no node (all-in runouts have no
      // further decisions; very thin runouts can be absent from a pack).
      return _message(context,
          icon: Icons.casino_outlined,
          title: 'No decisions on this runout',
          body: 'This line has no further action to study (an all-in line, '
              'or a runout the pack does not carry).',
          action: back());
    }
    // Street closed by matched action. All-in call → showdown, no more cards
    // to pick meaningfully street by street.
    final streetSteps =
        state.line.reversed.takeWhile((s) => !s.startsWith('@')).toList();
    final allinCall = last.startsWith('CALL') &&
        streetSteps.any((s) => s.toUpperCase().startsWith('ALLIN'));
    final dealt = state.dealtCards.length;
    if (allinCall) {
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreetCardPicker(
              title: dealt == 0 ? 'Pick the turn card' : 'Pick the river card',
              excluded: excluded,
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
      mainAxisAlignment: MainAxisAlignment.end,
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
