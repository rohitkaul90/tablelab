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
class _Spec {
  final String id;
  final List<String> board;
  final List<String> hero;
  final int heroSeat;
  final int stack;
  final List<HandAction> flop;
  final String note;
  const _Spec(this.id, this.board, this.hero, this.heroSeat, this.stack,
      this.flop, this.note);
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
];

PokerHand _buildHand(_Spec s) {
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
        seatIndex: s.heroSeat == 0 ? 2 : 0,
        name: 'Villain',
        startingStack: s.stack,
      ),
    ],
    streets: [
      // BTN (seat 0) opens to 5, BB (seat 2) calls — single-raised, heads-up.
      const StreetData(street: Street.preflop, actions: [
        HandAction(seat: 2, type: ActionType.post, amount: 2),
        HandAction(seat: 0, type: ActionType.raise, amount: 5),
        HandAction(seat: 2, type: ActionType.call, amount: 5),
      ]),
      StreetData(
          street: Street.flop, communityCards: s.board, actions: s.flop),
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
    final ok = gto.isNotEmpty;
    if (ok) fired.add(s);
    stdout.writeln('${ok ? '✓' : '✗'} ${s.id}  scenario=${check?.scenarioKey}  '
        '— ${s.note}');
    if (ok) {
      // Show the rendered mix so we can eyeball the class/facing it resolved to.
      final m = RegExp(r'flop \(([^)]*)\): ([^;.\]]*)').firstMatch(gto.first);
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
