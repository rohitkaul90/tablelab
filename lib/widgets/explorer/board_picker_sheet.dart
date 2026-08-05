// GTO Explorer — the solved-board picker sheet: filter chips (suitedness /
// pairing / high card A..2) + text search over a LAZY board list. The spot
// list arrives through [loadSpots] (the provider's per-scenario index fetch),
// so the sheet opens instantly and shows its own spinner / retryable error —
// at full density a scenario lists ~1,755 boards, which is why the list is a
// builder with a fixed itemExtent and the filter facets are parsed ONCE per
// load (board_filter.dart), not per keystroke.
//
// Plain StatefulWidget (no Riverpod) — widget-testable with a faked loader.

import 'package:flutter/material.dart';

import '../../equity/card.dart';
import '../../equity/texture_cell.dart';
import '../../explorer/board_filter.dart';
import '../../explorer/pack_source.dart';
import 'board_cards.dart';

class BoardPickerSheet extends StatefulWidget {
  final String title;

  /// The currently loaded board (highlighted), if any.
  final String? selectedFlop;

  /// The depth-regime preference: a tapped board picks its spot at this spr
  /// when solved, else falls back to the board's first spot.
  final String? preferredSpr;

  /// Fetches the scenario's spots (sorted). THROWS on failure — the sheet
  /// shows a retryable error state, never a silent empty list.
  final Future<List<ExplorerSpotRef>> Function() loadSpots;

  /// Called with the chosen spot AFTER the sheet pops. The caller guards its
  /// own mounted state (the sheet is its own route and can outlive it).
  final void Function(ExplorerSpotRef spot) onPick;

  const BoardPickerSheet({
    super.key,
    required this.title,
    required this.loadSpots,
    required this.onPick,
    this.selectedFlop,
    this.preferredSpr,
  });

  @override
  State<BoardPickerSheet> createState() => _BoardPickerSheetState();
}

class _BoardPickerSheetState extends State<BoardPickerSheet> {
  static const double _rowExtent = 48;

  bool _loading = true;
  bool _failed = false;

  /// Unique boards in discovery order + their spots and precomputed facets —
  /// built ONCE per successful load.
  List<BoardInfo> _infos = const [];
  Map<String, List<ExplorerSpotRef>> _byFlop = const {};
  List<String> _presentRanks = const []; // A..2 order, only ranks that occur

  final Set<SuitPattern> _suits = {};
  final Set<Pairing> _pairing = {};
  final Set<String> _highRanks = {};
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final spots = await widget.loadSpots();
      if (!mounted) return;
      final byFlop = <String, List<ExplorerSpotRef>>{};
      for (final s in spots) {
        (byFlop[s.flop] ??= []).add(s);
      }
      final infos = buildBoardInfos(byFlop.keys.toList());
      final present = {for (final i in infos) i.highRankChar};
      setState(() {
        _loading = false;
        _byFlop = byFlop;
        _infos = infos;
        _presentRanks = [
          for (final r in kMatrixRanks)
            if (present.contains(r)) r
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  BoardFilter get _filter => BoardFilter(
        suits: _suits,
        pairing: _pairing,
        highRanks: _highRanks,
        query: _query.text,
      );

  void _pick(String flop) {
    final forFlop = _byFlop[flop];
    if (forFlop == null || forFlop.isEmpty) return;
    final pick = forFlop.firstWhere((s) => s.spr == widget.preferredSpr,
        orElse: () => forFlop.first);
    Navigator.of(context).pop();
    widget.onPick(pick);
  }

  @override
  Widget build(BuildContext context) {
    // isScrollControlled sheet: take most of the screen, and lift above the
    // keyboard so the search field is never covered.
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.85,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(widget.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              Expanded(child: _content(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            const Text("Couldn't load the board list"),
            const SizedBox(height: 4),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final filtered = applyBoardFilter(_infos, _filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search boards (e.g. Ks 9)',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(_query.clear),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _chipRow(context, [
          for (final s in SuitPattern.values)
            _chip(suitPatternLabel(s), _suits.contains(s),
                (on) => setState(() => on ? _suits.add(s) : _suits.remove(s))),
          for (final p in Pairing.values)
            _chip(
                pairingLabel(p),
                _pairing.contains(p),
                (on) =>
                    setState(() => on ? _pairing.add(p) : _pairing.remove(p))),
        ]),
        if (_presentRanks.length > 1)
          _chipRow(context, [
            for (final r in _presentRanks)
              _chip(
                  r,
                  _highRanks.contains(r),
                  (on) => setState(
                      () => on ? _highRanks.add(r) : _highRanks.remove(r))),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text(
            '${filtered.length} of ${_infos.length} boards',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('No boards match',
                      style: TextStyle(color: scheme.onSurfaceVariant)))
              : ListView.builder(
                  itemExtent: _rowExtent,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) =>
                      _boardRow(context, filtered[i]),
                ),
        ),
      ],
    );
  }

  /// One horizontally-scrolling chip row (13 rank chips don't fit a phone).
  Widget _chipRow(BuildContext context, List<Widget> chips) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in chips)
            Padding(padding: const EdgeInsets.only(right: 6), child: c),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, void Function(bool) onChanged) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: onChanged,
    );
  }

  Widget _boardRow(BuildContext context, BoardInfo info) {
    final selected = info.flop == widget.selectedFlop;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _pick(info.flop),
      child: Container(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.25)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            BoardCardsRow(info.flop.split(' ')),
            const SizedBox(width: 10),
            Expanded(
              child: Text(info.flop,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
