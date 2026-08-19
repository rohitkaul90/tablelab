import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/pc_chart_keys.dart';
import 'package:tablelab/equity/weighted_ranges.dart';

void main() {
  late PcRangeLibrary lib;

  setUpAll(() {
    lib = PcRangeLibrary.fromJsonString(
        File('assets/pc_ranges.json').readAsStringSync());
  });

  group('parsing', () {
    test('loads the full bundled slice', () {
      expect(lib.charts.length, 1073);
      // 8-max only in the asset; both games present.
      expect(lib.charts.every((c) => c.table == '8max'), isTrue);
      expect(lib.charts.map((c) => c.game).toSet(), {'cash', 'mtt'});
    });

    test('action ids decode', () {
      expect(pcActionKind('f'), PcActionKind.fold);
      expect(pcActionKind('c'), PcActionKind.call);
      expect(pcActionKind('r:12'), PcActionKind.raise);
      expect(pcActionKind('a:100'), PcActionKind.allIn);
      expect(pcActionSize('r:12'), 12);
      expect(pcActionSize('a:16.995'), 16.995);
      expect(pcActionSize('c'), isNull);
    });
  });

  group('known chart values', () {
    test('cash 100bb BB vs BTN open matches validated numbers', () {
      final ch = lib.find(
          game: 'cash', bbs: 100, hero: 'BB', node: 'vs_open', villains: ['BTN']);
      expect(ch, isNotNull);
      // Values cross-checked against the raw dataset during acquisition.
      expect(ch!.callFreq('KJs'), closeTo(0.46, 0.001));
      expect(ch.raiseFreq('KJs'), closeTo(0.54, 0.001));
      expect(ch.raiseFreq('TT'), closeTo(1.0, 0.001));
      expect(ch.foldFreq('72o'), closeTo(1.0, 0.001));
      // Every audit-flagged hand defends fully.
      for (final h in ['TT', '99', 'KJs', 'KTs', 'KQo', 'AJo']) {
        expect(ch.continueFreq(h), closeTo(1.0, 0.001), reason: h);
      }
      // Aggregates: defend ~38%, 3-bet ~12.7% of combos.
      expect(ch.comboShare((a) => pcActionKind(a) != PcActionKind.fold) * 100,
          closeTo(38.2, 0.5));
      expect(
          ch.comboShare((a) =>
                  pcActionKind(a) == PcActionKind.raise ||
                  pcActionKind(a) == PcActionKind.allIn) *
              100,
          closeTo(12.7, 0.5));
    });

    test('cash 100bb BTN rfi opens ~40% at 3bb', () {
      final ch = lib.find(game: 'cash', bbs: 100, hero: 'BTN', node: 'rfi');
      expect(ch, isNotNull);
      final open = ch!.comboShare((a) => pcActionKind(a) != PcActionKind.fold);
      expect(open * 100, closeTo(40.3, 0.5));
      final sizes = ch.actions.map(pcActionSize).whereType<double>();
      expect(sizes, contains(3)); // PC BTN opens to 3bb
    });

    test('unreachable hands are null-safe zeros', () {
      // An MTT all-in response chart excludes hands hero never holds there.
      final ch = lib.charts.firstWhere(
          (c) => c.node.startsWith('vs_allin') && c.hands.values.contains(null));
      final nullHand =
          ch.hands.entries.firstWhere((e) => e.value == null).key;
      expect(ch.continueFreq(nullHand), 0);
      expect(ch.foldFreq(nullHand), 0);
    });
  });

  group('depth snapping', () {
    test('mtt depths snap to nearest, ties prefer deeper', () {
      final d = lib.depthsFor('mtt', '8max', 'BTN', 'rfi');
      expect(d, containsAll([12, 20, 30, 50, 80]));
      final ch = lib.find(game: 'mtt', bbs: 35, hero: 'BTN', node: 'rfi');
      expect(ch!.bbs, 30); // 35 is closer to 30 than 40 (40 not bundled)
      final tie = lib.find(game: 'mtt', bbs: 25, hero: 'BTN', node: 'rfi');
      expect(tie!.bbs, 30); // exact tie 20/30 → deeper
    });

    test('cash snaps between 100 and 200', () {
      expect(lib.find(game: 'cash', bbs: 120, hero: 'CO', node: 'rfi')!.bbs, 100);
      expect(lib.find(game: 'cash', bbs: 180, hero: 'CO', node: 'rfi')!.bbs, 200);
    });
  });

  group('seat mapping', () {
    test('late positions anchor; blinds map directly', () {
      expect(pcSeatFor('BTN', 9), 'BTN');
      expect(pcSeatFor('CO', 9), 'CO');
      expect(pcSeatFor('HJ', 9), 'HJ');
      expect(pcSeatFor('SB', 9), 'SB');
      expect(pcSeatFor('BB', 9), 'BB');
      expect(pcSeatFor('STR', 9), 'BB');
    });

    test('9-max early seats compress onto the PC ladder', () {
      expect(pcSeatFor('MP', 9), 'LJ');
      expect(pcSeatFor('UTG+2', 9), 'UTG1');
      expect(pcSeatFor('UTG+1', 9), 'UTG');
      expect(pcSeatFor('UTG', 9), 'UTG'); // clamped
    });

    test('6-max UTG is the lojack — the audit fix', () {
      expect(pcSeatFor('UTG', 6), 'LJ');
      expect(pcSeatFor('HJ', 6), 'HJ');
    });

    test('8-max app labels map one-to-one', () {
      expect(pcSeatFor('UTG', 8), 'UTG');
      expect(pcSeatFor('UTG+1', 8), 'UTG1');
      expect(pcSeatFor('MP', 8), 'LJ');
    });
  });

  group('resolution', () {
    test('BB defending a 6-max UTG open uses the LJ chart', () {
      final ch = resolvePcChart(lib,
          tournament: false,
          tableSeats: 6,
          effectiveBb: 100,
          heroLabel: 'BB',
          node: PcNode.vsOpen,
          openerLabel: 'UTG');
      expect(ch, isNotNull);
      expect(ch!.villains, ['LJ']);
    });

    test('rfi binary view thresholds sensibly', () {
      final hands = pcRfiHands(lib,
          tournament: false,
          tableSeats: 9,
          effectiveBb: 100,
          heroLabel: 'BTN');
      expect(hands, isNotNull);
      expect(hands!, contains('A2s'));
      expect(hands, isNot(contains('72o')));
      // ~40% opening range lands near 40% of the 169 grid weighted by combos.
      final combos =
          hands.fold<int>(0, (s, h) => s + combosOfHand(h)) / 1326 * 100;
      expect(combos, inInclusiveRange(30, 50));
    });

    test('squeeze node resolves with raiser + caller', () {
      final ch = resolvePcChart(lib,
          tournament: false,
          tableSeats: 9,
          effectiveBb: 100,
          heroLabel: 'BTN',
          node: PcNode.vsRaiseCall,
          openerLabel: 'UTG',
          callerLabel: 'HJ');
      expect(ch, isNotNull);
      expect(ch!.villains.length, 2);
    });
  });
}
