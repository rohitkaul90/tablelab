import 'package:flutter/material.dart';
import '../../equity/card.dart';
import '../../equity/gto_ranges.dart';
import 'card_picker.dart';
import 'range_matrix.dart';

const List<String> kPositions = [
  'UTG', 'UTG+1', 'UTG+2', 'MP', 'HJ', 'CO', 'BTN', 'SB', 'BB',
];

class PlayerRangeEditor extends StatefulWidget {
  final String position;
  final Set<int> selectedCells;
  final Set<String> takenPositions;
  final bool isExactHand;
  final int? card1;
  final int? card2;
  final Set<int> excludedCards; // board + other players' exact cards
  final void Function(String position, Set<int> cells, bool isExactHand, int? card1, int? card2) onSave;
  final VoidCallback? onDelete;

  /// Preset list to offer; null falls back to the legacy [gtoPresets] (used
  /// only while the PC weighted library is still loading — the caller passes
  /// the PC-derived presets once available).
  final List<GtoPreset>? presets;

  const PlayerRangeEditor({
    super.key,
    required this.position,
    required this.selectedCells,
    required this.takenPositions,
    required this.onSave,
    this.isExactHand = false,
    this.card1,
    this.card2,
    this.excludedCards = const {},
    this.onDelete,
    this.presets,
  });

  @override
  State<PlayerRangeEditor> createState() => _PlayerRangeEditorState();
}

class _PlayerRangeEditorState extends State<PlayerRangeEditor> {
  late String _position;
  late Set<int> _cells;
  String? _selectedPreset;
  late bool _isExactHand;
  int? _card1;
  int? _card2;

  @override
  void initState() {
    super.initState();
    _position = widget.position;
    _cells = Set<int>.from(widget.selectedCells);
    _isExactHand = widget.isExactHand;
    _card1 = widget.card1;
    _card2 = widget.card2;
  }

  // Pinned for the sheet's lifetime (the caller resolves the PC-vs-legacy
  // choice ONCE at sheet-open) and memoized: the range-matrix drag paints a
  // setState per crossed cell, so per-build regrouping would run dozens of
  // times per stroke.
  late final List<GtoPreset> _presets = widget.presets ?? gtoPresets;
  late final Map<String, List<GtoPreset>> _presetsByCategory =
      widget.presets == null ? gtoPresetsByCategory : _groupByCategory();

  Map<String, List<GtoPreset>> _groupByCategory() {
    final out = <String, List<GtoPreset>>{};
    for (final p in _presets) {
      out.putIfAbsent(p.category, () => []).add(p);
    }
    return out;
  }

  void _applyPreset(String key) {
    // orElse guard: a stale key (e.g. state restored across a preset-source
    // change) must never throw in release — it just doesn't apply.
    final preset = _presets.where((p) => p.key == key).firstOrNull;
    if (preset == null) return;
    setState(() {
      _selectedPreset = key;
      _cells = handSetToCells(preset.hands);
    });
  }

  // Both hole cards in one sheet visit — the picker stays open until two
  // cards are chosen (mirrors the flop picker / hand-recording UX).
  void _pickHoleCards(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => HoleCardsPickerSheet(
        excludedCards: widget.excludedCards,
        currentCards: [_card1, _card2],
        onConfirm: (cards) => setState(() {
          _card1 = cards[0];
          _card2 = cards[1];
        }),
      ),
    );
  }

  void _clearAll() => setState(() => _cells = {});

  void _selectAll() {
    setState(() {
      _cells = {for (int r = 0; r < 13; r++) for (int c = 0; c < 13; c++) r * 13 + c};
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availablePositions = kPositions
        .where((p) => p == _position || !widget.takenPositions.contains(p))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Text('Edit Range', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () {
                        widget.onDelete!();
                        Navigator.pop(context);
                      },
                    ),
                  TextButton(
                    onPressed: () {
                      widget.onSave(_position, _cells, _isExactHand, _card1, _card2);
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(
                    12, 0, 12, 12 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Position selector
                    Row(
                      children: [
                        const Text('Position:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        _DropdownContainer(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _position,
                              isDense: true,
                              items: availablePositions
                                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _position = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Mode toggle
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Range')),
                        ButtonSegment(value: true, label: Text('Exact Hand')),
                      ],
                      selected: {_isExactHand},
                      onSelectionChanged: (s) => setState(() => _isExactHand = s.first),
                    ),
                    const SizedBox(height: 16),
                    if (_isExactHand) ...[
                      // Exact hand picker
                      const Text('Select hole cards:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _ExactCardSlot(
                            cardIdx: _card1,
                            label: 'Card 1',
                            onTap: () => _pickHoleCards(context),
                          ),
                          const SizedBox(width: 16),
                          _ExactCardSlot(
                            cardIdx: _card2,
                            label: 'Card 2',
                            onTap: () => _pickHoleCards(context),
                          ),
                          if (_card1 != null || _card2 != null) ...[
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(() { _card1 = null; _card2 = null; }),
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                      if (_card1 != null && _card2 != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${cardName(_card1!)} — ${cardName(_card2!)}',
                          style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.70),
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ] else ...[
                      // GTO preset selector
                      const Text('Load GTO Preset:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      _DropdownContainer(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPreset,
                            isExpanded: true,
                            hint: const Text('Select preset...'),
                            items: [
                              for (final entry in _presetsByCategory.entries) ...[
                                DropdownMenuItem<String>(
                                  value: '__header_${entry.key}',
                                  enabled: false,
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                for (final preset in entry.value)
                                  DropdownMenuItem<String>(
                                    value: preset.key,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(preset.label),
                                    ),
                                  ),
                              ]
                            ],
                            onChanged: (v) {
                              if (v != null && !v.startsWith('__header_')) _applyPreset(v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Quick actions
                      Row(
                        children: [
                          TextButton(onPressed: _clearAll, child: const Text('Clear All')),
                          const SizedBox(width: 8),
                          TextButton(onPressed: _selectAll, child: const Text('Select All')),
                          const Spacer(),
                          RangeStats(selectedCells: _cells),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Legend
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _LegendDot(color: Colors.amber, label: 'Pairs'),
                          const SizedBox(width: 12),
                          _LegendDot(color: Colors.green.shade600, label: 'Suited'),
                          const SizedBox(width: 12),
                          _LegendDot(color: Colors.blue.shade600, label: 'Offsuit'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Matrix
                      RangeMatrix(
                        selectedCells: _cells,
                        onChanged: (cells) {
                          setState(() {
                            _cells = cells;
                            _selectedPreset = null;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DropdownContainer extends StatelessWidget {
  final Widget child;
  const _DropdownContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _ExactCardSlot extends StatelessWidget {
  final int? cardIdx;
  final String label;
  final VoidCallback onTap;

  const _ExactCardSlot({this.cardIdx, required this.label, required this.onTap});

  Color _suitColor(int s) {
    switch (s) {
      case 0: return Colors.green.shade300;
      case 1: return Colors.blue.shade300;
      case 2: return Colors.red.shade400;
      case 3: return Colors.purple.shade300;
      default: return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: cardIdx == null
              ? Container(
                  width: 68, height: 94,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: theme.colorScheme.primary.withAlpha(180), width: 1.5,
                        style: BorderStyle.solid),
                  ),
                  child: Center(
                    child: Text('?',
                        style: TextStyle(fontSize: 36, color: theme.colorScheme.primary.withAlpha(180))),
                  ),
                )
              : Container(
                  width: 68, height: 94,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _suitColor(cardSuit(cardIdx!)), width: 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(kRankChars[cardRank(cardIdx!)],
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.bold,
                              color: _suitColor(cardSuit(cardIdx!)))),
                      Text(kSuitSymbols[cardSuit(cardIdx!)],
                          style: TextStyle(fontSize: 20, color: _suitColor(cardSuit(cardIdx!)))),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
