import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows the rank×suit card-picker bottom sheet used by hand recording.
///
/// Always presented in the dark theme: the picker's suit glyphs and sheet
/// colors are tuned for the green-felt look, and Quick Hand opens it from
/// light-themed screens too.
Future<List<String>?> showHandCardPicker(
  BuildContext context, {
  required int count,
  Set<String> used = const {},
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => Theme(
      data: AppTheme.dark,
      child: HandCardPicker(count: count, used: used),
    ),
  );
}

/// Card-picker grid: ranks as rows, suits as columns, multi-tap selection up
/// to [count]. Cards in [used] are disabled. Pops with the selected cards in
/// 'As'/'Kh' notation, or null when dismissed.
class HandCardPicker extends StatefulWidget {
  final int count;
  final Set<String> used;
  const HandCardPicker({super.key, required this.count, required this.used});

  @override
  State<HandCardPicker> createState() => _HandCardPickerState();
}

class _HandCardPickerState extends State<HandCardPicker> {
  static const _ranks = [
    'A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5', '4', '3', '2'
  ];
  static const _suits = ['s', 'h', 'd', 'c'];
  static const _suitSymbols = {'s': '♠', 'h': '♥', 'd': '♦', 'c': '♣'};
  static const _suitColors = {
    's': Colors.white,
    'h': Color(0xFFEF5350),
    'd': Color(0xFFEF5350),
    'c': Colors.white,
  };

  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Text(
              'Select ${widget.count} card${widget.count > 1 ? 's' : ''}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text('${_selected.length}/${widget.count}',
                style: const TextStyle(color: Colors.white54)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            const SizedBox(width: 24),
            ..._suits.map((s) => Expanded(
                  child: Center(
                    child: Text(_suitSymbols[s]!,
                        style: TextStyle(
                            fontSize: 16,
                            color: _suitColors[s],
                            fontWeight: FontWeight.bold)),
                  ),
                )),
          ]),
        ),
        const Divider(height: 8),
        Expanded(
          child: ListView.builder(
            controller: sc,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _ranks.length,
            itemBuilder: (_, ri) {
              final rank = _ranks[ri];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(
                    width: 24,
                    child: Text(rank == 'T' ? '10' : rank,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                            fontWeight: FontWeight.bold)),
                  ),
                  ..._suits.map((suit) {
                    final card = '$rank$suit';
                    final isUsed = widget.used.contains(card);
                    final isSel = _selected.contains(card);
                    return Expanded(
                      child: GestureDetector(
                        onTap: isUsed
                            ? null
                            : () {
                                setState(() {
                                  if (isSel) {
                                    _selected.remove(card);
                                  } else if (_selected.length <
                                      widget.count) {
                                    _selected.add(card);
                                  }
                                });
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.all(2),
                          height: 44,
                          decoration: BoxDecoration(
                            color: isUsed
                                ? Colors.grey[900]
                                : isSel
                                    ? Theme.of(context).colorScheme.primary
                                    : const Color(0xFF2A2A3E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSel
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                rank == 'T' ? '10' : rank,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isUsed
                                      ? Colors.white12
                                      : _suitColors[suit],
                                ),
                              ),
                              Text(
                                _suitSymbols[suit]!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isUsed
                                      ? Colors.white12
                                      : _suitColors[suit],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ]),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: _selected.length == widget.count
                  ? () => Navigator.pop(context, _selected.toList())
                  : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: Text(
                _selected.length == widget.count
                    ? 'Confirm — ${_selected.join(' ')}'
                    : 'Select ${widget.count - _selected.length} more',
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
