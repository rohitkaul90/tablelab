// GTO Explorer — the PREFLOP TRAIL: a 6-max position strip where the user
// taps out the preflop sequence (fold to the opener → a responder calls or
// 3-bets → the opener responds), the grid shows the acting player's PRESET
// range at the inspected decision, and the right pane's action cards show
// each action's share OF HANDS ("% of hands" — presets are ranges, not mixed
// solver frequencies) and act as grid FILTERS like postflop. A completed
// sequence that maps to a solved scenario offers "Study postflop →".

import 'package:flutter/material.dart';

import '../../explorer/preflop_ranges.dart';
import 'strategy_grid.dart';

class PreflopTrailView extends StatefulWidget {
  /// Scenario keys with at least one browsable solved spot.
  final Set<String> availableScenarios;
  final void Function(String scenarioKey) onStudyPostflop;
  const PreflopTrailView({
    super.key,
    required this.availableScenarios,
    required this.onStudyPostflop,
  });

  @override
  State<PreflopTrailView> createState() => _PreflopTrailViewState();
}

class _PreflopTrailViewState extends State<PreflopTrailView> {
  bool _trn = false; // cash | tournament charts
  String? _opener;
  String? _responder;
  String? _responderAction; // 'Call' | '3-bet'
  String? _openerResponse; // 'Call' | '4-bet' (only after a 3-bet)
  int _viewStep = 0; // 0 opener · 1 responder · 2 opener-vs-3-bet
  int? _filterAction;

  static const Map<String, Color> _kActionColors = {
    'Raise': Color(0xFFA23030),
    '3-bet': Color(0xFFA23030),
    '4-bet': Color(0xFF8C2323),
    'Call': Color(0xFF3E9B4F),
    'Fold': Color(0xFF4A7BB5),
  };

  void _reset() => setState(() {
        _opener = null;
        _responder = null;
        _responderAction = null;
        _openerResponse = null;
        _viewStep = 0;
        _filterAction = null;
      });

  PreflopDecision? _decision() {
    final opener = _opener;
    if (opener == null) return null;
    return switch (_viewStep) {
      0 => openerDecision(opener, trn: _trn),
      1 => _responder == null
          ? null
          : responderDecision(_responder!, opener, trn: _trn),
      _ => _responder == null
          ? null
          : openerVs3BetDecision(opener, _responder!, trn: _trn),
    };
  }

  /// Can [pos] still take on the responder role?
  bool _canRespond(String pos) {
    if (_opener == null || _responder != null) return false;
    if (pos == _opener) return false;
    // Blinds always act after the open; other seats only if AFTER the opener.
    if (pos == 'SB' || pos == 'BB') return true;
    return kTrailPositions.indexOf(pos) > kTrailPositions.indexOf(_opener!);
  }

  Future<void> _positionTap(String pos) async {
    // Assign roles first; boxes with roles switch the inspected decision.
    if (_opener == null) {
      if (pos == 'BB') return; // no opening chart (the BB never opens first)
      setState(() {
        _opener = pos;
        _viewStep = 0;
        _filterAction = null;
      });
      return;
    }
    if (pos == _opener) {
      // Facing a 3-bet with no response yet → choose it; otherwise inspect.
      if (_responderAction == '3-bet' && _openerResponse == null) {
        final choice = await _choose('$_opener vs the 3-bet', ['Call', '4-bet']);
        if (choice != null) {
          setState(() {
            _openerResponse = choice;
            _viewStep = 2;
            _filterAction = null;
          });
        }
        return;
      }
      setState(() {
        _viewStep = 0;
        _filterAction = null;
      });
      return;
    }
    if (pos == _responder) {
      setState(() {
        _viewStep = 1;
        _filterAction = null;
      });
      return;
    }
    if (_canRespond(pos)) {
      final choice = await _choose('$pos vs the $_opener open', ['Call', '3-bet']);
      if (choice != null) {
        setState(() {
          _responder = pos;
          _responderAction = choice;
          _openerResponse = null;
          _viewStep = 1;
          _filterAction = null;
        });
      }
    }
  }

  Future<String?> _choose(String title, List<String> options) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final o in options)
              ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: _kActionColors[o], shape: BoxShape.circle),
                ),
                title: Text(o),
                onTap: () => Navigator.of(sheetContext).pop(o),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decision = _decision();

    return Column(
      children: [
        _strip(context),
        const Divider(height: 1),
        Expanded(
          child: decision == null
              ? _hint(context)
              : LayoutBuilder(builder: (context, constraints) {
                  final grid = _grid(context, decision);
                  final panel = _actionPanel(context, decision);
                  if (constraints.maxWidth >= 900) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 11, child: grid),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 9, child: panel),
                      ],
                    );
                  }
                  return ListView(
                    children: [grid, SizedBox(height: 380, child: panel)],
                  );
                }),
        ),
        Container(
          width: double.infinity,
          color: scheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            'Preflop preset ranges — a hand is in or out of a range; '
            'percentages are each action\'s share of hands, not mixed '
            'frequencies',
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

  Widget _strip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    (String, Color?, bool)? roleOf(String pos) {
      // (label under the seat, box color, viewable)
      if (pos == _opener) {
        final extra = _openerResponse != null ? ' · $_openerResponse' : '';
        return ('Raise$extra', _kActionColors['Raise'], true);
      }
      if (pos == _responder) {
        return (_responderAction!, _kActionColors[_responderAction!], true);
      }
      if (_opener != null) {
        final foldsBeforeOpen = !_canRespond(pos) && pos != _opener;
        if (foldsBeforeOpen || _responder != null) {
          return ('Fold', null, false);
        }
      }
      return null;
    }

    final viewedPos = switch (_viewStep) {
      0 => _opener,
      1 => _responder,
      _ => _opener,
    };

    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final pos in kTrailPositions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: () {
                final role = roleOf(pos);
                final isViewed = role != null &&
                    role.$3 &&
                    pos == viewedPos &&
                    // The opener box reads as "viewed" for steps 0 and 2.
                    !(pos == _opener && _viewStep == 1);
                return Material(
                  color: role?.$2?.withValues(alpha: 0.30) ??
                      (role != null
                          ? scheme.surfaceContainerLow
                          : scheme.surfaceContainerHighest),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: isViewed
                        ? BorderSide(
                            color: scheme.primary.withValues(alpha: 0.7),
                            width: 1.4)
                        : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _positionTap(pos),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(pos,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                          Text(
                            role?.$1 ?? '—',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: role?.$2 ?? scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }(),
            ),
          Center(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('Cash')),
                ButtonSegment(value: true, label: Text('Trn')),
              ],
              selected: {_trn},
              onSelectionChanged: (s) => setState(() {
                _trn = s.first;
                _filterAction = null;
              }),
            ),
          ),
          const SizedBox(width: 8),
          Center(
            child: TextButton.icon(
              onPressed: _opener == null ? null : _reset,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Tap a position to open',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Positions before the opener fold. Then tap a later position '
                '(or a blind) to choose its response — the grid shows each '
                'player\'s preset range as the action unfolds.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, PreflopDecision d) {
    final cells = preflopGridCells(d);
    final colors = [for (final a in d.actions) _kActionColors[a] ?? Colors.grey];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, c) {
        final side = !c.maxHeight.isFinite
            ? c.maxWidth
            : [c.maxWidth, c.maxHeight]
                .reduce((a, b) => a < b ? a : b)
                .clamp(120.0, 4096.0);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: StrategyGrid(
              cells: cells,
              actionColors: colors,
              filterAction: _filterAction,
            ),
          ),
        );
      }),
    );
  }

  Widget _actionPanel(BuildContext context, PreflopDecision d) {
    final scheme = Theme.of(context).colorScheme;
    final shares = d.shares;
    final combos = d.comboCounts;
    final scenario = _opener == null
        ? null
        : trailScenarioKey(
            opener: _opener!,
            responder: _responder,
            responderAction: _responderAction,
            openerResponse: _openerResponse,
            trn: _trn,
          );
    final canStudy =
        scenario != null && widget.availableScenarios.contains(scenario);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('${d.actorLabel} — ${_stepLabel()}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('ACTIONS · % of hands · tap to filter the grid',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        for (var a = 0; a < d.actions.length; a++)
          _actionCard(context, a, d.actions[a],
              _kActionColors[d.actions[a]] ?? Colors.grey, shares[a],
              combos[a]),
        if (scenario != null) ...[
          const SizedBox(height: 10),
          Material(
            color: canStudy
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: canStudy ? () => widget.onStudyPostflop(scenario) : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.school_outlined,
                        size: 20,
                        color: canStudy
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        canStudy
                            ? 'This spot is solved — study the postflop play'
                            : 'This spot type is solved, but its packs are '
                                'not available on this device yet',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: canStudy
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant),
                      ),
                    ),
                    if (canStudy)
                      Icon(Icons.arrow_forward,
                          size: 18, color: scheme.onPrimaryContainer),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _stepLabel() => switch (_viewStep) {
        0 => 'opening range',
        1 => 'vs the $_opener open',
        _ => 'vs the $_responder 3-bet',
      };

  Widget _actionCard(BuildContext context, int index, String label,
      Color color, double share, int comboCount) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filterAction == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: selected ? 0.45 : 0.22),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? BorderSide(color: color, width: 1.6)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => setState(
              () => _filterAction = _filterAction == index ? null : index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('$comboCount combos',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text('${(share * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Icon(selected ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 18,
                    color:
                        selected ? scheme.onSurface : scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
