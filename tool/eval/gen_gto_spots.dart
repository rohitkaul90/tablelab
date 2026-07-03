// Generate covered-config eval spots that EXERCISE the GTO-frequency FACT.
//
// The Pluribus benchmark plays ~100bb (deep SPR) 6-max, so after the v1
// library's correct restrictions (BTN-opener vs BB, single-raised, heads-up,
// shallow/medium SPR, covered texture) it produces ZERO `[HEURISTIC — GTO
// frequency]` lines — the eval can't see the feature. This builds a small set
// of synthetic BTN-vs-BB hands that DO hit the library, spanning hero position,
// facing-node, hand class, SPR bucket, and texture.
//
// Self-verifying: for each spec it computes the real equity check + facts (with
// the library) and prints whether the GTO FACT fired and what it says, so the
// set can be curated. Writes each hand as a PokerHand JSON (tool/eval/samples/
// gto/) and merges spots.json entries (idempotent by id).
//
//   dart run tool/eval/gen_gto_spots.dart           # report only
//   dart run tool/eval/gen_gto_spots.dart --write    # write files + spots.json

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/equity/gto_frequency_library.dart';
import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';

const String _outDir = 'tool/eval/samples/gto';
const String _spotsPath = 'tool/eval/spots.json';

/// One synthetic spot. heroSeat 0 = BTN (IP), 2 = BB (OOP). [stack] sets the SPR
/// regime (30 → shallow ~2.5, 50 → medium ~4.5). [flop] is the post-flop action
/// producing the intended facing-node for hero.
///
/// When [turn] (the single turn card) is set, the spot is a TURN-decision spot:
/// [flop] must fully resolve the flop (both players act — typically check/check
/// or bet/call), and [turnAct] produces hero's facing-node on the turn. The
/// turn-street SPR re-buckets from the flop line (a flop bet/call shrinks it),
/// so pair stacks with flop action to land committed/shallow/medium.
///
/// When [river] (the single river card) is set, the spot is a RIVER-decision
/// spot: [flop] AND [turnAct] must both fully resolve, and [riverAct] produces
/// hero's facing-node on the river. River cells exist only after the river solve
/// (TLSOLVE_PROFILE=river dump_rounds 3) — until then these report ✗ and --write
/// skips them; tune the river card / hand class against the solved library.
class _Spec {
  final String id;
  final List<String> board;
  final List<String> hero;
  final int heroSeat;
  final int stack;
  final List<HandAction> flop;
  final String note;
  final String? turn;
  final List<HandAction> turnAct;
  final String? river;
  final List<HandAction> riverAct;

  /// 3-bet-pot spot (scenario 3bp_bb_v_btn): preflop becomes BTN open 5 →
  /// BB 3-bet 18 → BTN call (pot 36 at the flop). [stack] then sets the 3bp
  /// SPR regime: 52 → committed (~0.94), 90 → shallow (2.0), 160 → medium (~3.9).
  final bool threeBet;

  /// Which seat opens (single-raised specs): 0 = BTN (srp_late_v_bb),
  /// 3 = UTG (srp_early_v_bb), 5 = CO (srp_middle_v_bb) — 6-max, buttonSeat 0.
  final int openerSeat;
  const _Spec(this.id, this.board, this.hero, this.heroSeat, this.stack,
      this.flop, this.note,
      {this.turn,
      this.turnAct = const [],
      this.river,
      this.riverAct = const [],
      this.threeBet = false,
      this.openerSeat = 0});
}

// Action shorthands.
HandAction _chk(int s) => HandAction(seat: s, type: ActionType.check);
HandAction _bet(int s, int a) =>
    HandAction(seat: s, type: ActionType.raise, amount: a);
HandAction _call(int s, int a) =>
    HandAction(seat: s, type: ActionType.call, amount: a);

// Boards (covered textures, present at both shallow+medium in the v1 library):
//   A = As Kd 7h  rainbow|unpaired|ace|disconnected
//   B = 9s 8d 6c  rainbow|unpaired|middling|connected
//   C = Qh Th 9c  twotone|unpaired|broadway|connected
const _boardA = ['As', 'Kd', '7h'];
const _boardB = ['9s', '8d', '6c'];
const _boardC = ['Qh', 'Th', '9c'];

final List<_Spec> _specs = [
  // IP (BTN), facing a check (the c-bet decision) — the highest-value node.
  _Spec('gto-ip-fcheck-marg-sh', _boardA, ['Ac', 'Qd'], 0, 30,
      [_chk(2), _bet(0, 4)], 'IP facing_check, top pair (marginalMade), shallow'),
  _Spec('gto-ip-fcheck-strong-md', _boardA, ['7s', '7c'], 0, 50,
      [_chk(2), _bet(0, 5)], 'IP facing_check, set (strongMade), medium'),
  _Spec('gto-ip-fcheck-air-sh', _boardA, ['9c', '4d'], 0, 30,
      [_chk(2), _bet(0, 4)], 'IP facing_check, air, shallow'),
  _Spec('gto-ip-fcheck-sdraw-md', _boardB, ['Jc', 'Tc'], 0, 50,
      [_chk(2), _bet(0, 5)], 'IP facing_check, OESD (strongDraw), medium'),
  _Spec('gto-ip-fcheck-sdraw-sh', _boardC, ['Ah', 'Kh'], 0, 30,
      [_chk(2), _bet(0, 4)], 'IP facing_check, nut FD (strongDraw), shallow'),
  // IP (BTN), facing a donk bet.
  _Spec('gto-ip-fbet-marg-md', _boardA, ['Ac', 'Qd'], 0, 50,
      [_bet(2, 5), _call(0, 5)], 'IP facing_bet (BB donk), top pair, medium'),
  // OOP (BB), first to act — villain must also act so position is determinable.
  _Spec('gto-oop-fta-marg-sh', _boardA, ['Ac', 'Qd'], 2, 30, [_chk(2), _chk(0)],
      'OOP first_to_act (check-through), top pair, shallow'),
  _Spec('gto-oop-fta-air-md', _boardA, ['9c', '4d'], 2, 50, [_chk(2), _chk(0)],
      'OOP first_to_act (check-through), air, medium'),
  _Spec('gto-oop-fta-strong-md', _boardA, ['7s', '7c'], 2, 50,
      [_bet(2, 5), _call(0, 5)], 'OOP first_to_act (lead), set, medium'),
  _Spec('gto-oop-fta-sdraw-sh', _boardB, ['Jc', 'Tc'], 2, 30,
      [_bet(2, 3), _call(0, 3)], 'OOP first_to_act (lead), OESD, shallow'),
  // OOP (BB), facing a c-bet.
  _Spec('gto-oop-fbet-marg-sh', _boardA, ['Ac', 'Qd'], 2, 30,
      [_chk(2), _bet(0, 4), _call(2, 4)], 'OOP facing_bet, top pair, shallow'),
  _Spec('gto-oop-fbet-wdraw-md', _boardB, ['Tc', '4d'], 2, 50,
      [_chk(2), _bet(0, 5), _call(2, 5)], 'OOP facing_bet, gutshot (weakDraw), medium'),

  // ── TURN-decision spots (phase 2b: exercise the flop+turn library cells) ──
  // Turn cards chosen so the 4-card board maps to a populated texture cell.
  // Flop action sets the turn SPR: check/check keeps the full ~4.5/2.5 SPR
  // (medium/shallow); a flop bet/call shrinks it toward committed.
  //   TA  = boardA + Ks  → As Kd 7h Ks  twotone|paired|ace|disconnected
  //   TA2 = boardA + 2c  → As Kd 7h 2c  rainbow|unpaired|ace|disconnected
  //   TB  = boardB + 5s  → 9s 8d 6c 5s  twotone|unpaired|middling|connected
  //   TC2 = boardC + 2c  → Qh Th 9c 2c  twotone|unpaired|broadway|connected

  // IP (BTN) turn nodes.
  _Spec('gto-t-ip-fcheck-strong-md', _boardA, ['7s', '7c'], 0, 50,
      [_chk(2), _chk(0)], 'TURN IP facing_check, set (strongMade), medium',
      turn: 'Ks', turnAct: [_chk(2), _bet(0, 7)]),
  _Spec('gto-t-ip-fcheck-air-sh', _boardA, ['9s', '4d'], 0, 30,
      [_chk(2), _chk(0)], 'TURN IP facing_check, air, shallow',
      turn: '2c', turnAct: [_chk(2), _bet(0, 4)]),
  _Spec('gto-t-ip-fbet-marg-md', _boardA, ['Ac', 'Qd'], 0, 50,
      [_chk(2), _chk(0)], 'TURN IP facing_bet (BB leads), top pair, medium',
      turn: '2c', turnAct: [_bet(2, 6), _call(0, 6)]),
  _Spec('gto-t-ip-fbet-sdraw-co', _boardB, ['Jh', 'Td'], 0, 30,
      [_chk(2), _bet(0, 5), _call(2, 5)],
      'TURN IP facing_bet (BB leads), OESD (strongDraw), committed',
      turn: '5s', turnAct: [_bet(2, 8), _call(0, 8)]),

  // OOP (BB) turn nodes.
  _Spec('gto-t-oop-fta-strong-md', _boardA, ['7s', '7c'], 2, 50,
      [_chk(2), _chk(0)], 'TURN OOP first_to_act (lead), set (strongMade), medium',
      turn: 'Ks', turnAct: [_bet(2, 6), _call(0, 6)]),
  _Spec('gto-t-oop-fta-air-md', _boardA, ['9s', '4d'], 2, 50,
      [_chk(2), _chk(0)], 'TURN OOP first_to_act (check-through), air, medium',
      turn: '2c', turnAct: [_chk(2), _chk(0)]),
  _Spec('gto-t-oop-fbet-marg-sh', _boardA, ['Ac', 'Qd'], 2, 30,
      [_chk(2), _chk(0)], 'TURN OOP facing_bet (mid), top pair, shallow',
      turn: '4s', turnAct: [_chk(2), _bet(0, 6), _call(2, 6)]),
  _Spec('gto-t-oop-fbet-wdraw-md', _boardA, ['5c', '4c'], 2, 50,
      [_chk(2), _chk(0)],
      'TURN OOP facing_bet, wheel gutshot (weakDraw), medium',
      turn: '2c', turnAct: [_chk(2), _bet(0, 6), _call(2, 6)]),
  _Spec('gto-t-oop-fta-sdraw-md', _boardB, ['Jh', 'Td'], 2, 50,
      [_chk(2), _chk(0)], 'TURN OOP first_to_act (lead), OESD (strongDraw), medium',
      turn: '5s', turnAct: [_bet(2, 6), _call(0, 6)]),
  _Spec('gto-t-oop-fraise-strong-sh', ['Kh', '7h', '2c'], ['7s', '7d'], 2, 50,
      [_bet(2, 5), _call(0, 5)],
      'TURN OOP facing_raise, sevens-full (strongMade), shallow',
      turn: 'Kd', turnAct: [_bet(2, 6), _bet(0, 16), _call(2, 16)]),

  // ── RIVER-decision spots (phase 2c) — TEMPLATES. These exercise river cells,
  // which only exist after the river solve (TLSOLVE_PROFILE=river → dump_rounds 3).
  // Until then gen_gto_spots reports them ✗ and --write skips them. After the
  // solve, tune the river card / hand class to a POPULATED cell, then --write.
  // Flop + turn both check through (full board, river SPR ≈ flop SPR). Spread
  // across the three texture classes (A rainbow-ace / B middling-connected /
  // C twotone-broadway) so river coverage isn't confined to one board.
  _Spec('gto-r-ip-fcheck-strong-md', _boardA, ['7s', '7c'], 0, 50,
      [_chk(2), _chk(0)], 'RIVER IP facing_check, sevens-full (strongMade), medium',
      turn: '2c', turnAct: [_chk(2), _chk(0)],
      river: '2d', riverAct: [_chk(2), _bet(0, 8)]),
  _Spec('gto-r-oop-fta-marg-md', _boardC, ['Qc', 'Jd'], 2, 50,
      [_chk(2), _chk(0)], 'RIVER OOP first_to_act (lead), top pair Q (marginalMade), medium',
      turn: '2s', turnAct: [_chk(2), _chk(0)],
      river: '3d', riverAct: [_bet(2, 8), _call(0, 8)]),
  _Spec('gto-r-oop-fbet-marg-sh', _boardB, ['9h', 'Tc'], 2, 30,
      [_chk(2), _chk(0)], 'RIVER OOP facing_bet (bluff-catch), top pair 9, shallow',
      turn: '2s', turnAct: [_chk(2), _chk(0)],
      river: '3d', riverAct: [_chk(2), _bet(0, 6), _call(2, 6)]),
  _Spec('gto-r-ip-fbet-strong-md', _boardB, ['6h', '6d'], 0, 50,
      [_chk(2), _chk(0)], 'RIVER IP facing_bet, set of sixes (strongMade), medium',
      turn: '2s', turnAct: [_chk(2), _chk(0)],
      river: '3d', riverAct: [_bet(2, 8), _call(0, 8)]),

  // ── 3-BET-POT spots (scenario 3bp_bb_v_btn — SOLVED 2026-07-02, Cycle A;
  // all 7 fire ✓ and are written). Preflop: BTN opens 5, BB 3-bets to 18, BTN
  // calls → pot 36 at the flop; the aggressor (BB) is OOP. Stacks 52/90/160
  // land committed/shallow/medium (see _Spec.threeBet). Spread hero position ×
  // facing × hand class × SPR regime + one turn + one river decision.
  // ⚠️ REMEMBER: --write emits samples/ + spots.json only — the eval scorer
  // reads tool/eval/fixtures/, so new spots MUST also be BAKED
  // (dart run tool/eval/bake_fixtures.dart) or the eval never exercises them.
  _Spec('gto-3bp-oop-cbet-strong-sh', _boardA, ['Ah', 'Kc'], 2, 90,
      [_bet(2, 24), _call(0, 24)],
      '3BP OOP first_to_act (c-bet), top two (strongMade), shallow',
      threeBet: true),
  _Spec('gto-3bp-oop-fta-marg-md', _boardA, ['Qc', 'Qd'], 2, 160,
      [_chk(2), _chk(0)],
      '3BP OOP first_to_act (check), QQ under the ace (marginalMade), medium',
      threeBet: true),
  _Spec('gto-3bp-ip-fcheck-marg-co', _boardA, ['Ac', 'Qd'], 0, 52,
      [_chk(2), _bet(0, 16)],
      '3BP IP facing_check, top pair (marginalMade), committed',
      threeBet: true),
  // Faced-bet sizes must land in the flop tree's NATIVE buckets (33% → small,
  // 75% → big; there is no native flop 'mid' — 50–67% sizings miss the cell).
  _Spec('gto-3bp-ip-fbet-strong-md', _boardB, ['9h', '9c'], 0, 160,
      [_bet(2, 27), _call(0, 27)],
      '3BP IP facing_bet (75% c-bet), top set (strongMade), medium',
      threeBet: true),
  _Spec('gto-3bp-oop-fbet-air-sh', _boardC, ['Ac', '4d'], 2, 90,
      [_chk(2), _bet(0, 12), _call(2, 12)],
      '3BP OOP facing_bet (33%), ace-high (air), shallow',
      threeBet: true),
  _Spec('gto-3bp-t-ip-fbet-marg-sh', _boardA, ['Ac', 'Qd'], 0, 90,
      [_chk(2), _chk(0)],
      '3BP TURN IP facing_bet (BB delays), top pair (marginalMade), shallow',
      threeBet: true, turn: '2c', turnAct: [_bet(2, 20), _call(0, 20)]),
  _Spec('gto-3bp-r-oop-fta-strong-md', _boardA, ['Ah', 'Kc'], 2, 160,
      [_chk(2), _chk(0)],
      '3BP RIVER OOP first_to_act (lead), top two (strongMade), medium',
      threeBet: true, turn: '2c', turnAct: [_chk(2), _chk(0)],
      river: '3d', riverAct: [_bet(2, 24), _call(0, 24)]),

  // ── EARLY-opener SRP spots (scenario srp_early_v_bb, UTG = seat 3 —
  // Cycle B) — TEMPLATES until solved; ✗ / skipped by --write until then.
  // Same pot shape as srp-late (open 5, BB call → pot 10; stacks 30/50 →
  // shallow/medium). Faced flop bets use native-leaning sizes (4 = 40% →
  // small, 8 = 80% → big); turn/river 6 = 60% → mid (native 66%).
  _Spec('gto-e-ip-fcheck-marg-sh', _boardA, ['Ac', 'Qd'], 3, 30,
      [_chk(2), _bet(3, 4)],
      'EARLY IP facing_check, top pair (marginalMade), shallow',
      openerSeat: 3),
  _Spec('gto-e-oop-fbet-marg-md', _boardA, ['Ac', 'Qd'], 2, 50,
      [_chk(2), _bet(3, 8), _call(2, 8)],
      'EARLY OOP facing_bet (big), top pair, medium',
      openerSeat: 3),
  _Spec('gto-e-oop-fta-strong-md', _boardA, ['7s', '7c'], 2, 50,
      [_bet(2, 4), _call(3, 4)],
      'EARLY OOP first_to_act (lead), set (strongMade), medium',
      openerSeat: 3),
  _Spec('gto-e-t-ip-fcheck-strong-md', _boardA, ['7s', '7c'], 3, 50,
      [_chk(2), _chk(3)],
      'EARLY TURN IP facing_check, set (strongMade), medium',
      openerSeat: 3, turn: 'Ks', turnAct: [_chk(2), _bet(3, 6)]),
  _Spec('gto-e-r-oop-fbet-marg-sh', _boardB, ['9h', 'Tc'], 2, 30,
      [_chk(2), _chk(3)],
      'EARLY RIVER OOP facing_bet (bluff-catch), top pair 9, shallow',
      openerSeat: 3, turn: '2s', turnAct: [_chk(2), _chk(3)],
      river: '3d', riverAct: [_chk(2), _bet(3, 6), _call(2, 6)]),

  // ── MIDDLE-opener SRP spots (scenario srp_middle_v_bb, CO = seat 5 —
  // Cycle B) — TEMPLATES until solved.
  _Spec('gto-m-ip-fcheck-air-sh', _boardA, ['9c', '4d'], 5, 30,
      [_chk(2), _bet(5, 4)], 'MIDDLE IP facing_check, air, shallow',
      openerSeat: 5),
  _Spec('gto-m-oop-fbet-wdraw-md', _boardB, ['Tc', '4d'], 2, 50,
      [_chk(2), _bet(5, 4), _call(2, 4)],
      'MIDDLE OOP facing_bet (small), gutshot (weakDraw), medium',
      openerSeat: 5),
  _Spec('gto-m-oop-fta-marg-sh', _boardA, ['Ac', 'Qd'], 2, 30,
      [_chk(2), _chk(5)],
      'MIDDLE OOP first_to_act (check-through), top pair, shallow',
      openerSeat: 5),
  _Spec('gto-m-t-oop-fbet-marg-sh', _boardA, ['Ac', 'Qd'], 2, 30,
      [_chk(2), _chk(5)],
      'MIDDLE TURN OOP facing_bet (mid), top pair, shallow',
      openerSeat: 5, turn: '4s',
      turnAct: [_chk(2), _bet(5, 6), _call(2, 6)]),
  _Spec('gto-m-r-ip-fbet-strong-md', _boardB, ['6h', '6d'], 5, 50,
      [_chk(2), _chk(5)],
      'MIDDLE RIVER IP facing_bet, set of sixes (strongMade), medium',
      openerSeat: 5, turn: '2s', turnAct: [_chk(2), _chk(5)],
      river: '3d', riverAct: [_bet(2, 6), _call(5, 6)]),
];

PokerHand _buildHand(_Spec s) {
  // Villain = the other player in the heads-up pot: the opener when hero is
  // the BB, the BB when hero is the opener.
  final villainSeat = s.heroSeat == 2 ? s.openerSeat : 2;
  return PokerHand(
    id: s.id,
    userId: 'eval',
    playedAt: DateTime(2026, 6, 28),
    tableSetup: TableSetup(
      numSeats: 6,
      buttonSeat: 0,
      heroSeat: s.heroSeat,
      smallBlind: 1,
      bigBlind: 2,
    ),
    players: [
      HandPlayer(
        seatIndex: s.heroSeat,
        name: 'Hero',
        startingStack: s.stack,
        isHero: true,
        holeCards: s.hero,
      ),
      HandPlayer(
        seatIndex: villainSeat,
        name: 'Villain',
        startingStack: s.stack,
      ),
    ],
    streets: [
      // Single-raised: [openerSeat] opens to 5, BB (seat 2) calls — the
      // opener's seat picks the SRP scenario (BTN/UTG/CO → late/early/middle).
      // 3-bet (threeBet): BTN opens 5, BB 3-bets to 18, BTN calls — the
      // 3bp_bb_v_btn shape (BB aggressor, OOP; pot 36 at the flop).
      StreetData(
          street: Street.preflop,
          actions: s.threeBet
              ? const [
                  HandAction(seat: 2, type: ActionType.post, amount: 2),
                  HandAction(seat: 0, type: ActionType.raise, amount: 5),
                  HandAction(seat: 2, type: ActionType.raise, amount: 18),
                  HandAction(seat: 0, type: ActionType.call, amount: 18),
                ]
              : [
                  const HandAction(seat: 2, type: ActionType.post, amount: 2),
                  HandAction(
                      seat: s.openerSeat, type: ActionType.raise, amount: 5),
                  const HandAction(
                      seat: 2, type: ActionType.call, amount: 5),
                ]),
      StreetData(
          street: Street.flop, communityCards: s.board, actions: s.flop),
      // Per-street communityCards are INCREMENTAL: each street holds only its
      // OWN new cards (the turn = 1 card), and the full board is their
      // concatenation (hand_model: streets.expand((s) => s.communityCards)).
      // Do NOT put all 4 cards here — that double-counts the flop.
      if (s.turn != null)
        StreetData(
            street: Street.turn, communityCards: [s.turn!], actions: s.turnAct),
      if (s.river != null)
        StreetData(
            street: Street.river,
            communityCards: [s.river!],
            actions: s.riverAct),
    ],
    isTournament: false,
  );
}

Future<void> main(List<String> args) async {
  final write = args.contains('--write');
  final lib = GtoFrequencyLibrary.fromJsonString(
      File('assets/gto_freq_library.json').readAsStringSync());

  final fired = <_Spec>[];
  for (final s in _specs) {
    final hand = _buildHand(s);
    final check = await computeHandEquityCheck(hand, seed: 1234, iterations: 4000);
    final facts = check == null ? const <String>[] : equityCheckFacts(check, library: lib);
    final gto = facts.where((f) => f.contains('[HEURISTIC — GTO frequency')).toList();
    // Verify the FACT covers the spec's TARGET street, not merely that SOME GTO
    // FACT fired: a river spec's flop/turn nodes fire off the existing flop/turn
    // cells even when NO river cells exist, which would mask missing river
    // coverage. Requiring a `<street> (` segment makes a river spec read ✗ until
    // the river solve populates river cells (then ✓), so the set self-verifies.
    final street =
        s.river != null ? 'river' : (s.turn != null ? 'turn' : 'flop');
    final ok = gto.any((f) => f.contains('$street ('));
    if (ok) fired.add(s);
    stdout.writeln('${ok ? '✓' : '✗'} ${s.id}  scenario=${check?.scenarioKey}  '
        '— ${s.note}');
    if (ok) {
      // Show the rendered mix so we can eyeball the class/facing it resolved to.
      // Match the "(…)" descriptor lazily — the air hand class renders a NESTED
      // paren ("air (no real equity)"), so [^)]* would stop at the inner ")".
      final m = RegExp('$street \\((.*?)\\): ([^;.\\]]*)').firstMatch(gto.first);
      if (m != null) stdout.writeln('      ${m.group(1)} → ${m.group(2)?.trim()}');
    }
  }

  stdout.writeln('\n${fired.length}/${_specs.length} specs produced a GTO FACT.');

  if (!write) {
    stdout.writeln('(report only — re-run with --write to emit files + spots.json)');
    return;
  }

  Directory(_outDir).createSync(recursive: true);
  final newEntries = <Map<String, dynamic>>[];
  for (final s in fired) {
    final path = '$_outDir/${s.id}.json';
    File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_buildHand(s).toJson()));
    newEntries.add({
      'id': s.id,
      'file': path,
      'source': 'synthetic/gto',
      'hero': s.heroSeat,
      'bucket': 'gto-frequency',
      'notes': s.note,
      'reads': <dynamic>[],
    });
  }

  // Merge into spots.json, idempotent by id.
  final spots = (jsonDecode(File(_spotsPath).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final byId = {for (final e in spots) e['id'] as String: e};
  for (final e in newEntries) {
    byId[e['id'] as String] = e;
  }
  final merged = byId.values.toList()
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  File(_spotsPath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(merged));
  stdout.writeln('Wrote ${fired.length} hands to $_outDir and merged spots.json '
      '(${merged.length} total spots).');
}
