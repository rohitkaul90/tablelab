// GTO Explorer — the runout card picker shown when a street's action closes:
// a compact 13×4 grid of the deck, board cards disabled. The library stores
// only ONE suit-isomorphic representative per equivalent runout, so [available]
// (when supplied) restricts direct picks to the ones the pack actually solved —
// but an absent card whose suit-equivalent twin IS stored renders pickable
// (small ≡ badge) and routes to that representative: the twin is the same
// solved spot, not a gap.

import 'package:flutter/material.dart';

import '../../equity/card.dart';
import '../../explorer/board_iso.dart';
import 'board_cards.dart';

class StreetCardPicker extends StatelessWidget {
  final String title; // 'Pick the turn card'
  final Set<String> excluded; // card names already on the board

  /// Runout cards the pack actually solved. Null = no restriction (offer all);
  /// otherwise cards outside this set render disabled UNLESS [isoBoard] finds
  /// them a stored suit-equivalent representative to route to.
  final Set<String>? available;

  /// The suit-isomorphism context: the fixed board the pick lands on — the
  /// FLOP ONLY for a turn pick (changing the turn CLEARS any pinned river, so
  /// no later card constrains the classes), flop + stored turn for a river
  /// pick (the earlier street's card is fixed and rides in [excluded] too).
  /// When supplied with [available], an absent card with an available
  /// suit-equivalent renders ENABLED with a ≡ badge and taps through to the
  /// stored representative via [representativeFor]; null keeps the plain
  /// absent-= -disabled behavior.
  final List<String>? isoBoard;
  final void Function(String card) onPick;
  const StreetCardPicker({
    super.key,
    required this.title,
    required this.excluded,
    this.available,
    this.isoBoard,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Representatives must themselves be tappable — on a river pick the
    // stored turn rides in [excluded] as well as [isoBoard] (it's already on
    // the board, so it can't stand in), so routing targets are the available
    // cards minus the excluded ones.
    final routable = isoBoard == null
        ? null
        : available?.where((c) => !excluded.contains(c)).toSet();
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
                      '${kRankChars[r]}${kSuitChars[s]}', routable),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, ColorScheme scheme, String name,
      Set<String>? routable) {
    // Disabled = already on the board, OR a runout the library merged away
    // with NO stored suit-equivalent to stand in for it.
    final isExcluded = excluded.contains(name);
    final absent = available != null && !available!.contains(name);
    final rep = !isExcluded && absent && isoBoard != null && routable != null
        ? representativeFor(name, fixedCards: isoBoard!, available: routable)
        : null;
    final disabled = isExcluded || (absent && rep == null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: disabled
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: disabled ? null : () => _tap(context, name, rep),
          child: SizedBox(
            width: 30,
            height: 40,
            child: rep == null
                ? CardGlyph(
                    name,
                    color: disabled
                        ? scheme.onSurface.withValues(alpha: 0.2)
                        : null,
                  )
                : Stack(children: [
                    Positioned.fill(child: CardGlyph(name)),
                    // Bottom-right, not top-right: the FittedBox scales the
                    // row down on narrow phones and a top badge crowded the
                    // rank char at ~7px.
                    Positioned(
                      bottom: 1,
                      right: 2,
                      child: Text(
                        '≡',
                        style: TextStyle(
                            fontSize: 10,
                            height: 1.0,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }

  void _tap(BuildContext context, String name, String? rep) {
    if (rep != null) {
      // Transient equivalence hint — the strip will (correctly) show the
      // stored representative, so say why the card changed suit. Replace any
      // showing snackbar so rapid picks don't queue a backlog of stale hints.
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        content: Text(
            '${_symbol(name)} ≡ ${_symbol(rep)} here — suits are '
            'interchangeable'),
        duration: const Duration(seconds: 2),
      ));
    }
    onPick(rep ?? name);
  }

  /// 'As' → 'A♠'.
  String _symbol(String card) {
    final c = parseCard(card);
    return c < 0 ? card : cardRankChar(c) + cardSuitSymbol(c);
  }
}
