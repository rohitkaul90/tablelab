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
  /// The preflop trail (who opened / responded / answered the 3-bet) shown in
  /// the unified strip. Synced to the loaded spot's scenario when a spot is
  /// opened directly.
  PreflopTrail _trail = const PreflopTrail();

  /// Which PREFLOP decision the body inspects (0 open / 1 response / 2 vs
  /// 3-bet), or -1 when the body shows the postflop node at the cursor.
  int _preflopInspect = -1;
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
    // Keep the preflop strip in sync when a spot changes underneath it (the
    // init auto-select, or a board pick) — but never clobber a user-built
    // trail that already maps to the same scenario. ref.listen must live
    // DIRECTLY in build (not inside the Builder below — Riverpod asserts).
    ref.listen<ExplorerSpotRef?>(
        explorerProvider.select((s) => s.spot), (prev, next) {
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
    final scheme = Theme.of(context).colorScheme;

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
  /// postflop spot when the mapped scenario changed and packs exist for it.
  void _setTrail(PreflopTrail t, {int inspect = -1}) {
    setState(() {
      _trail = t;
      _preflopInspect = inspect;
    });
    final sc = t.scenarioKey;
    if (sc == null) return;
    final st = ref.read(explorerProvider);
    if (st.spot?.scenario == sc) return;
    final candidates = st.spots.where((s) => s.scenario == sc).toList();
    if (candidates.isNotEmpty) {
      ref.read(explorerProvider.notifier).selectSpot(candidates.first);
    }
  }

  /// The FLOP box tap: pick among the scenario's solved boards/depths.
  void _openBoardPicker(BuildContext context, ExplorerState state) {
    final sc = _trail.scenarioKey;
    if (sc == null) return;
    final candidates = state.spots.where((s) => s.scenario == sc).toList();
    if (candidates.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Solved boards — ${scenarioDisplayName(sc)}',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            const SizedBox(height: 4),
            for (final s in candidates)
              ListTile(
                dense: true,
                title: Text(s.flop,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(s.spr),
                selected: identical(s, state.spot),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _preflopInspect = -1);
                  ref.read(explorerProvider.notifier).selectSpot(s);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _postflopContent(BuildContext context, ExplorerState state) {
    if (state.spots.isEmpty) {
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

  Widget _vBox(BuildContext context,
      {required String header,
      required List<Widget> rows,
      VoidCallback? onHeaderTap,
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
                    child: Text(header,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurfaceVariant)),
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

  Widget _unifiedStrip(BuildContext context, ExplorerState state) {
    final scheme = Theme.of(context).colorScheme;
    final boxes = <Widget>[
      ..._preflopBoxes(context),
      _flopBox(context, state),
      ..._postflopBoxes(context, state),
      // Trn toggle + reset at the end of the scroll.
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 10),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('Cash')),
                ButtonSegment(value: true, label: Text('Trn')),
              ],
              selected: {_trail.trn},
              onSelectionChanged: (s) =>
                  _setTrail(_trail.withTrn(s.first), inspect: -1),
            ),
            TextButton(
              onPressed: _trail.opener == null
                  ? null
                  : () => _setTrail(_trail.reset(), inspect: -1),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 10.5)),
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    ];
    // Height must fit the TALLEST box (header + 3 action rows) with slack for
    // text scaling — a fixed-height horizontal list overflows loudly (21px
    // RenderFlex overflow at 104).
    return Container(
      height: 128,
      color: scheme.surfaceContainerLowest,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        children: [
          for (final b in boxes) Align(alignment: Alignment.topLeft, child: b)
        ],
      ),
    );
  }

  /// Preflop seat boxes (from the preset charts), plus the opener's vs-3-bet
  /// box when a 3-bet happened. Any seat's action row is tappable: it rebuilds
  /// the trail from that point (a new opener voids the response, etc.).
  List<Widget> _preflopBoxes(BuildContext context) {
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
          inspected: inspected));
    }

    // The opener's answer to a 3-bet.
    if (t.responderAction == '3-bet' && t.opener != null) {
      out.add(_vBox(
        context,
        header: '${t.opener} (vs 3-bet)',
        inspected: _preflopInspect == 2,
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
  /// board/depth), or the reason there isn't one.
  Widget _flopBox(BuildContext context, ExplorerState state) {
    final sc = _trail.scenarioKey;
    final spot = state.spot;
    final matched = sc != null && spot != null && spot.scenario == sc;
    final hasPacks =
        sc != null && state.spots.any((s) => s.scenario == sc);

    final String detail;
    if (!_trail.closed) {
      detail = '—';
    } else if (sc == null) {
      detail = _trail.trn ? 'cash only' : 'not solved';
    } else if (!hasPacks) {
      detail = 'no packs';
    } else if (matched) {
      detail = '${spot.flop} · ${spot.spr}';
    } else {
      detail = 'pick a board';
    }
    return _vBox(
      context,
      header: 'FLOP',
      inspected: false,
      dimmed: !hasPacks || !_trail.closed,
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
    final sc = _trail.scenarioKey;
    final spot = state.spot;
    if (sc == null ||
        spot == null ||
        spot.scenario != sc ||
        state.manifest == null ||
        state.flopNodes == null) {
      return const [];
    }
    final scenario = state.manifest!.scenario;
    final out = <Widget>[];

    // A BET for everything behind (or a CALL of one) reads '(all-in)' so the
    // committed-depth lines aren't a surprise when the runout has no nodes.
    String rowLabel(PackNode n, String action) {
      final u = action.toUpperCase();
      var allIn = false;
      if (u.startsWith('CALL')) {
        allIn = n.toCall >= n.behind - 1e-6;
      } else if (u.startsWith('BET')) {
        final amt =
            double.tryParse(RegExp(r'[0-9.]+').firstMatch(u)?.group(0) ?? '');
        allIn = amt != null && amt >= n.behind - 1e-6;
      }
      return '${actionDisplayLabel(action)}${allIn ? ' · all-in' : ''}';
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
        out.add(_vBox(
          context,
          header: river ? 'RIVER' : 'TURN',
          dimmed: i > state.cursor,
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
        onHeaderTap: () {
          setState(() => _preflopInspect = -1);
          ref.read(explorerProvider.notifier).setCursor(state.line.length);
        },
        rows: rows,
      ));
    }

    // Pending runout boxes / hand-over marker.
    final lineDealt = dealtSoFar;
    final ended = state.line.isNotEmpty &&
        state.line.last.toUpperCase().startsWith('FOLD');
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
        _vRow(context, 'Hand over', Colors.grey),
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
