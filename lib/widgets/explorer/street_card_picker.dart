// GTO Explorer — the runout card picker shown when a street's action closes:
// a compact 13×4 grid of the deck, board cards disabled. Every runout exists
// in a solved spot's tree, so any enabled card is a valid continuation.

import 'package:flutter/material.dart';

import '../../equity/card.dart';

class StreetCardPicker extends StatelessWidget {
  final String title; // 'Pick the turn card'
  final Set<String> excluded; // card names already on the board
  final void Function(String card) onPick;
  const StreetCardPicker({
    super.key,
    required this.title,
    required this.excluded,
    required this.onPick,
  });

  static const _suitColors = {
    'c': Color(0xFF6FBF73), // clubs — green (4-color deck reads faster)
    'd': Color(0xFF64A5E8), // diamonds — blue
    'h': Color(0xFFE57373), // hearts — red
    's': Color(0xFFE0E0E0), // spades — light on the dark felt
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (var s = 3; s >= 0; s--) ...[
          // FittedBox: 13 fixed-width cards ≈ 442px — on a 360–412dp phone an
          // unshrinkable Row overflowed and clipped the low ranks untappable.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var r = 12; r >= 0; r--)
                  _card(context, scheme,
                      '${kRankChars[r]}${kSuitChars[s]}'),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, ColorScheme scheme, String name) {
    final disabled = excluded.contains(name);
    final suit = name[1];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: disabled
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: disabled ? null : () => onPick(name),
          child: SizedBox(
            width: 30,
            height: 40,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name[0],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: disabled
                        ? scheme.onSurface.withValues(alpha: 0.2)
                        : _suitColors[suit],
                  ),
                ),
                Text(
                  kSuitSymbols[kSuitChars.indexOf(suit)],
                  style: TextStyle(
                    fontSize: 11,
                    height: 1,
                    color: disabled
                        ? scheme.onSurface.withValues(alpha: 0.2)
                        : _suitColors[suit],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
