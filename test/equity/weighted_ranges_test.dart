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
      expect(lib.charts.length, 1190);
      expect(lib.skippedCharts, 0);
      // 8-max + heads-up in the asset; both games present.
      expect(lib.charts.map((c) => c.table).toSet(), {'8max', 'hu'});
      expect(lib.charts.map((c) => c.game).toSet(), {'cash', 'mtt'});
    });

    test('a malformed chart is skipped, not fatal', () {
      final broken = PcRangeLibrary.fromJson({
        'charts': [
          {'id': 'bad'}, // missing every required field
          {
            'id': 'ok',
            'game': 'cash',
            'table': '8max',
            'bbs': 100,
            'hero': 'BTN',
            'node': 'rfi',
            'villains': [],
            'sequence': '',
            'actions': ['f', 'r:3'],
            'hands': {
              'AA': [0.0, 1.0]
            },
          },
        ]
      });
      expect(broken.skippedCharts, 1);
      expect(broken.charts.single.id, 'ok');
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
      // The emitter strips unreachable rows entirely — an absent hand must
      // behave as an all-zero row. Every vs_3bet chart excludes hands hero
      // never opened, so find one missing a trash hand.
      final ch = lib.charts.firstWhere((c) =>
          c.node == 'vs_3bet' && !c.hands.containsKey('72o'));
      expect(ch.continueFreq('72o'), 0);
      expect(ch.foldFreq('72o'), 0);
      expect(ch.freqWhere('72o', (_) => true), 0);
    });

    test('excludeHands rows no longer ship as fake 100% folds', () {
      // A BTN opener facing a 3-bet never holds 72o; before the excludeHands
      // fix these shipped as genuine fold rows inflating fold mass.
      final ch = lib.find(
          game: 'cash', bbs: 100, hero: 'BTN', node: 'vs_3bet', villains: ['SB']);
      expect(ch, isNotNull);
      expect(ch!.hands.containsKey('72o'), isFalse);
      expect(ch.hands.containsKey('AA'), isTrue);
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

    test('sequence variants disambiguate on facingAllIn', () {
      // The dataset holds BOTH "facing a sized 3-bet" and "facing a 3-bet jam"
      // at mtt 30bb UTG vs UTG1. Before the tie-break fix the jam chart was
      // permanently shadowed.
      WeightedChart? get(bool? jam) => lib.find(
          game: 'mtt',
          bbs: 30,
          hero: 'UTG',
          node: 'vs_3bet',
          villains: ['UTG1'],
          facingAllIn: jam);
      final sized = get(false)!;
      final jam = get(true)!;
      expect(sized.id, isNot(jam.id));
      expect(jam.actions.where((a) => pcActionKind(a) == PcActionKind.raise),
          isEmpty);
      expect(sized.actions.where((a) => pcActionKind(a) == PcActionKind.raise),
          isNotEmpty);
      expect(get(null)!.id, sized.id); // default = sized variant
    });

    test('9-max UTG+1 defending vs UTG open resolves (collision shift)', () {
      final ch = resolvePcChart(lib,
          tournament: false,
          tableSeats: 9,
          effectiveBb: 100,
          heroLabel: 'UTG+1',
          node: PcNode.vsOpen,
          openerLabel: 'UTG');
      expect(ch, isNotNull);
      expect(ch!.hero, 'UTG1'); // hero shifted later, opener keeps UTG
      expect(ch.villains, ['UTG']);
    });

    test('squeeze caller collision shifts the caller', () {
      final ch = resolvePcChart(lib,
          tournament: false,
          tableSeats: 9,
          effectiveBb: 100,
          heroLabel: 'BTN',
          node: PcNode.vsRaiseCall,
          openerLabel: 'UTG',
          callerLabel: 'UTG+1');
      expect(ch, isNotNull);
      expect(ch!.villains, ['UTG', 'UTG1']);
    });

    test('straddle opener maps early, not to a blind', () {
      final ch = resolvePcChart(lib,
          tournament: false,
          tableSeats: 9,
          effectiveBb: 100,
          heroLabel: 'BB',
          node: PcNode.vsOpen,
          openerLabel: 'STR');
      expect(ch, isNotNull);
      expect(ch!.villains, ['UTG']); // early-position aggressor model
    });

    test('heads-up routes to HU charts; 3-max returns null', () {
      final hu = resolvePcChart(lib,
          tournament: false,
          tableSeats: 2,
          effectiveBb: 100,
          heroLabel: 'BTN',
          node: PcNode.rfi);
      expect(hu, isNotNull);
      expect(hu!.table, 'hu');
      // HU opens are far wider than the full-ring ~40% chart.
      final open = hu.comboShare((a) => pcActionKind(a) != PcActionKind.fold);
      expect(open, greaterThan(0.6));

      final threeMax = resolvePcChart(lib,
          tournament: false,
          tableSeats: 3,
          effectiveBb: 100,
          heroLabel: 'BTN',
          node: PcNode.rfi);
      expect(threeMax, isNull);
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
