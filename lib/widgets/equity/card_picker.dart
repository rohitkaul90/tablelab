import 'package:flutter/material.dart';
import '../../equity/card.dart';

/// Single-card picker for Turn/River.
/// Tapping a card auto-confirms and closes.
class CardPickerSheet extends StatelessWidget {
  final Set<int> excludedCards;
  final int? currentCard;
  final ValueChanged<int?> onSelected; // null = clear

  const CardPickerSheet({
    super.key,
    required this.excludedCards,
    required this.onSelected,
    this.currentCard,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.52,
      minChildSize: 0.4,
      maxChildSize: 0.65,
      builder: (context, scroll) {
        return Column(
          children: [
            _handle(context),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Select Card', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (currentCard != null)
                    TextButton(
                      onPressed: () {
                        onSelected(null);
                        Navigator.pop(context);
                      },
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      12, 0, 12, 12 + MediaQuery.paddingOf(context).bottom),
                  child: _CardGrid(
                    excludedCards: excludedCards,
                    selectedCards: currentCard != null ? {currentCard!} : {},
                    onTap: (idx) {
                      onSelected(idx);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Flop picker — stays open until all 3 cards are selected, then auto-confirms.
class FlopCardPickerSheet extends StatefulWidget {
  final Set<int> excludedCards; // turn + river (not other flop cards)
  final List<int?> currentFlop; // length 3
  final ValueChanged<List<int?>> onConfirm;

  const FlopCardPickerSheet({
    super.key,
    required this.excludedCards,
    required this.currentFlop,
    required this.onConfirm,
  });

  @override
  State<FlopCardPickerSheet> createState() => _FlopCardPickerSheetState();
}

class _FlopCardPickerSheetState extends State<FlopCardPickerSheet> {
  late List<int?> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<int?>.from(widget.currentFlop);
  }

  Set<int> get _pickedSet => _selected.whereType<int>().toSet();

  void _onCardTap(int idx) {
    setState(() {
      final pos = _selected.indexOf(idx);
      if (pos >= 0) {
        // Deselect
        _selected[pos] = null;
      } else {
        // Fill first empty slot
        final empty = _selected.indexOf(null);
        if (empty >= 0) _selected[empty] = idx;
      }
    });
    // Auto-confirm when all 3 filled
    if (_selected.every((c) => c != null)) {
      widget.onConfirm(List<int?>.from(_selected));
      Navigator.pop(context);
    }
  }

  void _clearAll() => setState(() => _selected = [null, null, null]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filledCount = _selected.whereType<int>().length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.5,
      maxChildSize: 0.75,
      builder: (context, scroll) {
        return Column(
          children: [
            _handle(context),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Select Flop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text(
                    '($filledCount / 3)',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _clearAll, child: const Text('Clear')),
                ],
              ),
            ),
            // 3 slot preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  for (int i = 0; i < 3; i++) ...[
                    _FlopSlot(cardIdx: _selected[i], isNext: _selected[i] == null && _selected.indexOf(null) == i),
                    if (i < 2) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      12, 0, 12, 12 + MediaQuery.paddingOf(context).bottom),
                  child: _CardGrid(
                    excludedCards: widget.excludedCards,
                    selectedCards: _pickedSet,
                    onTap: _onCardTap,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FlopSlot extends StatelessWidget {
  final int? cardIdx;
  final bool isNext;

  const _FlopSlot({this.cardIdx, this.isNext = false});

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
    if (cardIdx == null) {
      return Container(
        width: 50, height: 70,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isNext ? theme.colorScheme.primary : theme.colorScheme.outline,
            width: isNext ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text('?', style: TextStyle(
            fontSize: 22,
            color: isNext ? theme.colorScheme.primary : theme.colorScheme.outline,
          )),
        ),
      );
    }
    final color = _suitColor(cardSuit(cardIdx!));
    return Container(
      width: 50, height: 70,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(kRankChars[cardRank(cardIdx!)],
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(kSuitSymbols[cardSuit(cardIdx!)],
              style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

// Shared card grid used by both pickers
class _CardGrid extends StatelessWidget {
  final Set<int> excludedCards;
  final Set<int> selectedCards; // highlighted cards
  final ValueChanged<int> onTap;

  const _CardGrid({
    required this.excludedCards,
    required this.selectedCards,
    required this.onTap,
  });

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
    return Column(
      children: [
        for (int s = 3; s >= 0; s--)
          Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(kSuitSymbols[s],
                    style: TextStyle(color: _suitColor(s), fontSize: 13),
                    textAlign: TextAlign.center),
              ),
              for (int ri = 12; ri >= 0; ri--)
                Expanded(child: _CardTile(
                  cardIdx: cardIndex(ri, s),
                  excluded: excludedCards.contains(cardIndex(ri, s)),
                  isSelected: selectedCards.contains(cardIndex(ri, s)),
                  suitColor: _suitColor(s),
                  onTap: () => onTap(cardIndex(ri, s)),
                )),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  final int cardIdx;
  final bool excluded;
  final bool isSelected;
  final Color suitColor;
  final VoidCallback onTap;

  const _CardTile({
    required this.cardIdx,
    required this.excluded,
    required this.isSelected,
    required this.suitColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rankChar = kRankChars[cardRank(cardIdx)];
    Color bg, fg;
    if (excluded) {
      bg = Colors.transparent;
      fg = Theme.of(context).colorScheme.outlineVariant;
    } else if (isSelected) {
      bg = suitColor;
      fg = Colors.black87;
    } else {
      bg = Theme.of(context).colorScheme.surfaceContainerHighest;
      fg = suitColor;
    }
    return GestureDetector(
      onTap: excluded ? null : onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: isSelected ? Border.all(color: suitColor, width: 1.5) : null,
        ),
        child: AspectRatio(
          aspectRatio: 0.7,
          child: Center(
            child: Text(rankChar,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: fg)),
          ),
        ),
      ),
    );
  }
}

// Compact card chip used on the board display
class BoardCardChip extends StatelessWidget {
  final int? cardIdx;
  final VoidCallback onTap;

  const BoardCardChip({super.key, required this.cardIdx, required this.onTap});

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
    if (cardIdx == null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 62,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Center(
            child: Text('?',
                style: TextStyle(
                    fontSize: 20,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.75))),
          ),
        ),
      );
    }
    final color = _suitColor(cardSuit(cardIdx!));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 62,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(kRankChars[cardRank(cardIdx!)],
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(kSuitSymbols[cardSuit(cardIdx!)],
                style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

Widget _handle(BuildContext context) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Container(
    width: 40, height: 4,
    decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline,
        borderRadius: BorderRadius.circular(2)),
  ),
);
