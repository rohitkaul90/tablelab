// GTO Explorer — shared card-glyph rendering: the 4-color-deck suit palette
// and the rank-over-suit glyph column, extracted from StreetCardPicker so the
// board-picker rows and the runout picker draw cards identically.

import 'package:flutter/material.dart';

import '../../equity/card.dart';

/// 4-color deck — reads faster than red/black on the dark felt.
const Map<String, Color> kSuitGlyphColors = {
  'c': Color(0xFF6FBF73), // clubs — green
  'd': Color(0xFF64A5E8), // diamonds — blue
  'h': Color(0xFFE57373), // hearts — red
  's': Color(0xFFE0E0E0), // spades — light on the dark felt
};

/// The rank char stacked over the suit symbol, both in the suit's color
/// ([color] overrides both — the pickers' disabled fade).
class CardGlyph extends StatelessWidget {
  final String card; // 'Ks'
  final Color? color;
  final double rankSize;
  final double suitSize;
  const CardGlyph(
    this.card, {
    super.key,
    this.color,
    this.rankSize = 13,
    this.suitSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final suit = card[1];
    final c = color ?? kSuitGlyphColors[suit];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          card[0],
          style: TextStyle(
            fontSize: rankSize,
            fontWeight: FontWeight.w800,
            color: c,
          ),
        ),
        Text(
          kSuitSymbols[kSuitChars.indexOf(suit)],
          style: TextStyle(fontSize: suitSize, height: 1, color: c),
        ),
      ],
    );
  }
}

/// A compact row of card tiles ('Ks 9h 4c' → three glyph chips) — the board
/// picker's row leading.
class BoardCardsRow extends StatelessWidget {
  final List<String> cards;
  final double width;
  final double height;
  const BoardCardsRow(
    this.cards, {
    super.key,
    this.width = 26,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: width,
                height: height,
                child: CardGlyph(card, rankSize: 12, suitSize: 10),
              ),
            ),
          ),
      ],
    );
  }
}
