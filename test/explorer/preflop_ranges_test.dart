import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/chart_keys.dart';
import 'package:tablelab/explorer/preflop_ranges.dart';

void main() {
  group('openerDecision', () {
    test('BTN opening: raise = the RFI preset, raise+fold covers all hands',
        () {
      final d = openerDecision('BTN', trn: false)!;
      expect(d.actions, ['Raise', 'Fold']);
      expect(d.ranges[0], presetByKey['cash_rfi_btn']);
      expect(d.comboCounts.reduce((a, b) => a + b), 1326);
      final shares = d.shares;
      expect(shares[0] + shares[1], closeTo(1.0, 1e-9));
      expect(shares[0], greaterThan(0.3)); // BTN opens wide
      expect(shares[0], lessThan(0.7));
    });

    test('the BB has no opening chart', () {
      expect(openerDecision('BB', trn: false), isNull);
    });

    test('UTG opens tighter than BTN', () {
      final utg = openerDecision('UTG', trn: false)!;
      final btn = openerDecision('BTN', trn: false)!;
      expect(utg.shares[0], lessThan(btn.shares[0]));
    });
  });

  group('responderDecision', () {
    test('BB vs BTN: 3-bet takes precedence over call; partitions all hands',
        () {
      final d = responderDecision('BB', 'BTN', trn: false);
      expect(d.actions, ['3-bet', 'Call', 'Fold']);
      expect(d.ranges[0].intersection(d.ranges[1]), isEmpty);
      expect(d.comboCounts.reduce((a, b) => a + b), 1326);
      // AA 3-bets and never merely calls under precedence.
      expect(d.ranges[0], contains('AA'));
      expect(d.ranges[1], isNot(contains('AA')));
    });
  });

  group('openerVs3BetDecision', () {
    test('scoped within the opener range; partitions it exactly', () {
      final d = openerVs3BetDecision('BTN', 'BB', trn: false);
      final open = presetByKey['cash_rfi_btn']!;
      expect(d.actions, ['4-bet', 'Call', 'Fold']);
      final union = d.ranges[0].union(d.ranges[1]).union(d.ranges[2]);
      expect(union, open);
      expect(d.ranges[0].intersection(d.ranges[1]), isEmpty);
      expect(d.ranges[0], contains('AA')); // 4-bet value keeps the top
      // Shares divide by the DECISION'S universe (the opened range), so they
      // sum to 1 — dividing by 1326 understated every vs-3-bet frequency.
      expect(d.shares.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });
  });

  group('preflopGridCells', () {
    test('one-hot action mix per hand; off-universe hands are absent', () {
      final d = openerVs3BetDecision('BTN', 'BB', trn: false);
      final cells = preflopGridCells(d);
      var present = 0;
      for (var r = 0; r < 13; r++) {
        for (var c = 0; c < 13; c++) {
          final cell = cells[r][c];
          if (cell == null) continue;
          present++;
          expect(cell.freqs.where((f) => f == 1.0), hasLength(1));
          expect(cell.freqs.where((f) => f == 0.0), hasLength(2));
        }
      }
      // Only the BTN's opened hands appear (72o etc. absent).
      expect(present, lessThan(169));
      expect(present, greaterThan(30));
    });
  });

  group('trailScenarioKey', () {
    test('maps the solved scenarios and only them', () {
      String? key({
        required String opener,
        String? responder,
        String? act,
        String? resp,
        bool trn = false,
      }) =>
          trailScenarioKey(
              opener: opener,
              responder: responder,
              responderAction: act,
              openerResponse: resp,
              trn: trn);

      expect(key(opener: 'BTN', responder: 'BB', act: 'Call'),
          'srp_late_v_bb');
      expect(key(opener: 'CO', responder: 'BB', act: 'Call'),
          'srp_middle_v_bb');
      expect(key(opener: 'UTG', responder: 'BB', act: 'Call'),
          'srp_early_v_bb');
      expect(key(opener: 'BTN', responder: 'BB', act: '3-bet', resp: 'Call'),
          '3bp_bb_v_btn');
      // Blind-vs-blind: the SB open takes its OWN scenario (opener OOP),
      // never the late-bucket BTN cells.
      expect(key(opener: 'SB', responder: 'BB', act: 'Call'), 'srp_sb_v_bb');
      // Excluded shapes.
      expect(key(opener: 'BTN', responder: 'SB', act: 'Call'), isNull);
      expect(key(opener: 'BTN', responder: 'BB', act: '3-bet', resp: '4-bet'),
          isNull);
      expect(key(opener: 'CO', responder: 'BB', act: '3-bet', resp: 'Call'),
          isNull);
      expect(key(opener: 'BTN', responder: 'BB', act: 'Call', trn: true),
          isNull);
    });
  });

  group('bb anchoring', () {
    test('bbPerUnit anchors the normalized pot-10 scale to bb', () {
      expect(bbPerUnit('srp_late_v_bb', 10), closeTo(0.55, 1e-9));
      // BvB flop pot is 5.0bb (no dead SB), not the 5.5 the other SRPs share.
      expect(bbPerUnit('srp_sb_v_bb', 10), closeTo(0.5, 1e-9));
      expect(bbPerUnit('3bp_bb_v_btn', 10), closeTo(2.25, 1e-9));
      expect(bbPerUnit('unknown_scenario', 10), isNull);
    });

    test('per-player preflop investment matches the flop anchor', () {
      // Each player commits half of (flop pot − dead SB): SRP 2.5, 3-bet 11.
      expect(perPlayerPreflopInvestBB('srp_late_v_bb'), closeTo(2.5, 1e-9));
      expect(perPlayerPreflopInvestBB('3bp_bb_v_btn'), closeTo(11.0, 1e-9));
      // Blind-vs-blind has NO dead SB (the SB's blind is part of its open):
      // each player still commits 2.5 into the 5.0 pot.
      expect(perPlayerPreflopInvestBB('srp_sb_v_bb'), closeTo(2.5, 1e-9));
      expect(perPlayerPreflopInvestBB('unknown'), isNull);
    });

    test('depthLabelBB maps SPR regimes to approximate starting stacks', () {
      expect(depthLabelBB('srp_late_v_bb', 'shallow'), '~20bb');
      expect(depthLabelBB('srp_late_v_bb', 'deep'), '~100bb');
      expect(depthLabelBB('3bp_bb_v_btn', 'committed'), '~30bb');
      expect(depthLabelBB('3bp_bb_v_btn', 'medium'), '~100bb');
      // An unmapped scenario/regime falls back to the raw regime name.
      expect(depthLabelBB('future_scenario', 'deep'), 'deep');
    });
  });

  group('effective stack (bb)', () {
    test('a seat box shows starting stack minus its posted blind', () {
      // Non-blind seats have nothing in yet → full starting stack.
      expect(preflopEffStackBB('UTG', 100), closeTo(100, 1e-9));
      expect(preflopEffStackBB('BTN', 100), closeTo(100, 1e-9));
      // Blinds are already posted.
      expect(preflopEffStackBB('SB', 100), closeTo(99.5, 1e-9));
      expect(preflopEffStackBB('BB', 100), closeTo(99.0, 1e-9));
    });

    test('the vs-3-bet box subtracts the opener already-committed open', () {
      expect(preflopEffStackBBVs3Bet(100), closeTo(97.5, 1e-9));
    });

    test('the flop chains from the same starting stack', () {
      // start − each player's preflop investment = the flop effective stack.
      final start = 82.5 + perPlayerPreflopInvestBB('srp_late_v_bb')!; // 85
      expect(preflopEffStackBB('BTN', start) - // opener before the open
          perPlayerPreflopInvestBB('srp_late_v_bb')!, closeTo(82.5, 1e-9));
    });
  });
}
