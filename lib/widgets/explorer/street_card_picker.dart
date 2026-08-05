// GTO Explorer — the runout card picker shown when a street's action closes:
// a compact 13×4 grid of the deck, board cards disabled. The library stores
// only ONE suit-isomorphic representative per equivalent runout, so [available]
// (when supplied) restricts the enabled cards to the ones the pack actually
// solved — picking a missing twin would dead-end into "no decisions".

import 'package:flutter/material.dart';

import '../../equity/card.dart';
import 'board_cards.dart';

class StreetCardPicker extends StatelessWidget {
  final String title; // 'Pick the turn card'
  final Set<String> excluded; // card names already on the board

  /// Runout cards the pack actually solved. Null = no restriction (offer all);
  /// otherwise cards outside this set render disabled (suit-equivalent twins the
  /// library merged away).
  final Set<String>? available;
  final void Function(String card) onPick;
  const StreetCardPicker({
    super.key,
    required this.title,
    required this.excluded,
    this.available,
    required this.onPick,
  });

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
    // Disabled = already on the board, OR a suit-equivalent runout the library
    // merged away (not in [available]).
    final disabled = excluded.contains(name) ||
        (available != null && !available!.contains(name));
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
            child: CardGlyph(
              name,
              color:
                  disabled ? scheme.onSurface.withValues(alpha: 0.2) : null,
            ),
          ),
        ),
      ),
    );
  }
}
