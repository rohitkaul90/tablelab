import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';
import 'package:tablelab/equity/texture_cell.dart';

List<int> _b(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

void main() {
  group('textureCell', () {
    test('under 3 cards is unclassifiable', () {
      expect(textureCell(_b('Ks 9h')), isNull);
      expect(textureCell(const []), isNull);
    });

    test('rainbow / unpaired / broadway / disconnected flop', () {
      expect(textureCell(_b('Ks 9h 4c'))!.key,
          'rainbow|unpaired|broadway|disconnected');
    });

    test('monotone / unpaired / ace / connected flop', () {
      expect(
          textureCell(_b('Ah Kh Qh'))!.key, 'monotone|unpaired|ace|connected');
    });

    test('paired low rainbow flop', () {
      expect(textureCell(_b('7c 7d 2s'))!.key,
          'rainbow|paired|low|disconnected');
    });

    test('monotone middling connected flop', () {
      expect(textureCell(_b('8c 9c Tc'))!.key,
          'monotone|unpaired|middling|connected');
    });

    test('rainbow connected broadway flop', () {
      expect(textureCell(_b('Js Td 9c'))!.key,
          'rainbow|unpaired|broadway|connected');
    });

    test('high-card buckets at the boundaries', () {
      // top rank 8 → middling; top rank 7 → low.
      expect(textureCell(_b('8h 5c 2d'))!.highCard, HighCard.middling);
      expect(textureCell(_b('7h 5c 2d'))!.highCard, HighCard.low);
      // K/Q/J → broadway; A → ace.
      expect(textureCell(_b('Jh 5c 2d'))!.highCard, HighCard.broadway);
      expect(textureCell(_b('Ah 5c 2d'))!.highCard, HighCard.ace);
    });

    test('texture is recomputed per street (turn adds a suit/card)', () {
      // Ks9h4c is rainbow; a spade turn makes it two-tone.
      expect(textureCell(_b('Ks 9h 4c'))!.suit, SuitPattern.rainbow);
      expect(textureCell(_b('Ks 9h 4c 2s'))!.key,
          'twotone|unpaired|broadway|disconnected');
    });

    test('ace plays low for the straight window (wheel)', () {
      // A-2-3 supplies a low straight window → connected.
      expect(textureCell(_b('Ah 2c 3d'))!.connectedness, Connectedness.connected);
    });

    test('value equality keys on the canonical string', () {
      expect(textureCell(_b('Ks 9h 4c')), textureCell(_b('Kd 9s 4h')));
    });
  });
}
