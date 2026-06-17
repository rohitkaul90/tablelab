// PHH (Poker Hand History, TOML) -> PokerHand parser for the eval harness.
//
// Source: github.com/uoftcprg/phh-dataset (Pluribus 6-max + curated cash/MTT
// hands). The spec lives at phh.readthedocs.io; we only consume the NLHE subset
// the dataset uses. A deliberately minimal hand-rolled TOML reader avoids adding
// a `toml` dependency during the launch freeze — the files only use strings,
// ints, int arrays, bools, and one string array (`actions`).
//
// PHH seat convention: blinds_or_straddles[0] is posted by p1, [1] by p2, so
// p1 = SB, p2 = BB, ..., last index = BTN, and preflop action opens UTG (p3 in
// 6-max). This maps onto the app's TableSetup (button = last seat for 3+ handed,
// p1 for heads-up — see TableSetup.preflopOrder/postflopOrder).
//
// `cbr X` is "complete/bet/raise TO X" — a CUMULATIVE per-street total, which is
// exactly HandAction.amount's convention, so amounts transfer directly. `cc` is
// check-or-call (resolved by whether a wager is outstanding); `f` is fold.
// Recorded villain hole cards are intentionally DROPPED (set null): the prompt
// never prints them and the equity cross-check ignores them — modeling villains
// by range at decision time is the harness's result-independence guarantee.

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/models/hand_model.dart';

/// One parsed PHH hand plus the raw fields the curator/baker may need.
class PhhHand {
  final Map<String, dynamic> raw; // parsed TOML fields
  final List<String> actionTokens; // the `actions` string array, verbatim

  PhhHand(this.raw, this.actionTokens);

  int get numSeats => (raw['starting_stacks'] as List).length;
  List<int> get startingStacks => _intList(raw['starting_stacks']);
  List<int> get blinds => _intList(raw['blinds_or_straddles']);
  List<int> get antes => raw['antes'] != null
      ? _intList(raw['antes'])
      : List.filled(numSeats, 0);

  // PHH chip counts are integers, but tolerate a float-valued token (e.g.
  // "20000.0" or cent amounts) instead of throwing an opaque CastError.
  static List<int> _intList(dynamic v) =>
      (v as List).map((e) => e is int ? e : (e as num).round()).toList();
  List<String> get playerNames {
    final p = raw['players'] as List?;
    if (p != null) return p.cast<String>();
    return List.generate(numSeats, (i) => 'p${i + 1}');
  }

  /// 1-based p-indices whose hole cards are dealt face-up ("d dh pN XxYy",
  /// not "????"). These are the only valid hero choices.
  Set<int> get knownHolePlayers {
    final out = <int>{};
    for (final t in actionTokens) {
      final m = RegExp(r'^d dh p(\d+) (\S+)$').firstMatch(t.trim());
      if (m != null && m.group(2) != '????') out.add(int.parse(m.group(1)!));
    }
    return out;
  }
}

/// Parse the narrow TOML subset PHH files use. Handles `key = value` with
/// string / int / bool scalars and `[...]` arrays (single- or multi-line),
/// stripping `# ...` comments outside of quotes.
Map<String, dynamic> parseToml(String content) {
  final out = <String, dynamic>{};
  // Join into a single logical stream but keep newlines so multi-line arrays
  // work; we walk key = value statements.
  final lines = content.split('\n');
  var i = 0;
  while (i < lines.length) {
    var line = _stripComment(lines[i]);
    if (line.trim().isEmpty || !line.contains('=')) {
      i++;
      continue;
    }
    final eq = line.indexOf('=');
    final key = line.substring(0, eq).trim();
    var valuePart = line.substring(eq + 1).trim();

    // Multi-line array: keep appending stripped lines until brackets balance.
    if (valuePart.startsWith('[') && _bracketDepth(valuePart) > 0) {
      final buf = StringBuffer(valuePart);
      while (_bracketDepth(buf.toString()) > 0 && i + 1 < lines.length) {
        i++;
        buf.write('\n');
        buf.write(_stripComment(lines[i]));
      }
      valuePart = buf.toString();
    }
    out[key] = _parseValue(valuePart);
    i++;
  }
  return out;
}

/// Strip a `#` comment that is not inside a single- or double-quoted string.
String _stripComment(String line) {
  var inS = false, inD = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == "'" && !inD) {
      inS = !inS;
    } else if (c == '"' && !inS) {
      inD = !inD;
    } else if (c == '#' && !inS && !inD) {
      return line.substring(0, i);
    }
  }
  return line;
}

int _bracketDepth(String s) {
  var depth = 0;
  var inS = false, inD = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == "'" && !inD) {
      inS = !inS;
    } else if (c == '"' && !inS) {
      inD = !inD;
    } else if (!inS && !inD) {
      if (c == '[') depth++;
      if (c == ']') depth--;
    }
  }
  return depth;
}

dynamic _parseValue(String v) {
  v = v.trim();
  if (v.startsWith('[')) {
    // Split on top-level commas (commas inside quotes don't split), then parse
    // each element independently via _parseScalar. This keeps BOTH quoted and
    // bare elements in a mixed array — the old "if any quote present, return
    // only the quoted matches" shortcut silently dropped every numeric element.
    final inner = v.substring(1, v.lastIndexOf(']'));
    return _splitArrayElements(inner).map(_parseScalar).toList();
  }
  return _parseScalar(v);
}

/// Split a TOML array body on its top-level commas. A comma inside a single- or
/// double-quoted string is part of the element, not a separator.
List<String> _splitArrayElements(String inner) {
  final out = <String>[];
  final buf = StringBuffer();
  var inS = false, inD = false;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (c == "'" && !inD) {
      inS = !inS;
      buf.write(c);
    } else if (c == '"' && !inS) {
      inD = !inD;
      buf.write(c);
    } else if (c == ',' && !inS && !inD) {
      final t = buf.toString().trim();
      if (t.isNotEmpty) out.add(t);
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  final last = buf.toString().trim();
  if (last.isNotEmpty) out.add(last);
  return out;
}

dynamic _parseScalar(String v) {
  v = v.trim();
  if ((v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))) {
    return v.substring(1, v.length - 1);
  }
  if (v == 'true') return true;
  if (v == 'false') return false;
  final n = int.tryParse(v);
  if (n != null) return n;
  final d = double.tryParse(v);
  if (d != null) return d;
  return v;
}

/// Parse a `.phh` file's text into a [PhhHand].
PhhHand parsePhhText(String content) {
  final raw = parseToml(content);
  final actions = ((raw['actions'] as List?) ?? const []).cast<String>();
  return PhhHand(raw, actions);
}

/// Build a [PokerHand] from a parsed PHH hand, viewed from [heroPlayer]'s seat
/// (1-based p-index; must be in [PhhHand.knownHolePlayers]).
///
/// [playedAt] is passed in (not `DateTime.now()`) so fixtures are reproducible.
PokerHand phhToPokerHand(
  PhhHand h, {
  required int heroPlayer,
  required String id,
  required DateTime playedAt,
  bool isTournament = false,
  String? tournamentStage,
  String? notes,
}) {
  final n = h.numSeats;
  if (heroPlayer < 1 || heroPlayer > n) {
    throw ArgumentError('heroPlayer $heroPlayer out of range 1..$n');
  }
  final stacks = h.startingStacks;
  final blinds = h.blinds;
  final antes = h.antes;
  final names = h.playerNames;

  // p_i (1-based) -> seat index (0-based) = i-1.
  final heroSeat = heroPlayer - 1;
  final buttonSeat = n == 2 ? 0 : n - 1;
  final sb = blinds.isNotEmpty ? blinds[0] : 0;
  final bb = blinds.length > 1 ? blinds[1] : 0;
  // A straddle shows up as a third positive entry in blinds_or_straddles.
  final straddle = blinds.length > 2 && blinds[2] > 0 ? blinds[2] : null;
  final ante = antes.any((a) => a > 0) ? antes.reduce((a, b) => a > b ? a : b) : null;

  final ts = TableSetup(
    numSeats: n,
    buttonSeat: buttonSeat,
    heroSeat: heroSeat,
    smallBlind: sb,
    bigBlind: bb,
    straddle: straddle,
    ante: ante,
  );

  // Hole cards from the deal actions; villains' are dropped (set null).
  final holeBySeat = <int, List<String>>{};
  for (final t in h.actionTokens) {
    final m = RegExp(r'^d dh p(\d+) (\S+)$').firstMatch(t.trim());
    if (m != null && m.group(2) != '????') {
      holeBySeat[int.parse(m.group(1)!) - 1] = _splitCards(m.group(2)!);
    }
  }

  final players = <HandPlayer>[
    for (var seat = 0; seat < n; seat++)
      HandPlayer(
        seatIndex: seat,
        name: seat < names.length ? names[seat] : 'p${seat + 1}',
        startingStack: stacks[seat],
        isHero: seat == heroSeat,
        holeCards: seat == heroSeat ? holeBySeat[seat] : null,
      ),
  ];

  final streets = _buildStreets(h, ts);

  return PokerHand(
    id: id,
    userId: 'eval',
    playedAt: playedAt,
    tableSetup: ts,
    players: players,
    streets: streets,
    notes: notes,
    tournamentStage: tournamentStage,
    isTournament: isTournament || tournamentStage != null,
  );
}

const _ranks = '23456789TJQKA';
const _suits = 'cdhs';

List<String> _splitCards(String s) {
  // "Qh5c" -> ["Qh","5c"]; "7s9cTc" -> ["7s","9c","Tc"]. A malformed token
  // (odd length, or a 2-char chunk that isn't a real rank+suit) is a Format
  // exception, not a silently-truncated card list — the baker skips the hand.
  if (s.isEmpty || s.length.isOdd) {
    throw FormatException('malformed card token: "$s"');
  }
  final out = <String>[];
  for (var i = 0; i < s.length; i += 2) {
    final card = s.substring(i, i + 2);
    if (!_ranks.contains(card[0]) || !_suits.contains(card[1])) {
      throw FormatException('invalid card "$card" in token "$s"');
    }
    out.add(card);
  }
  return out;
}

const _streetOrder = [Street.preflop, Street.flop, Street.turn, Street.river];

List<StreetData> _buildStreets(PhhHand h, TableSetup ts) {
  final n = ts.numSeats;
  // Per-seat committed chips this street, and total across the hand (for stack
  // caps + all-in detection).
  final streetContrib = List<int>.filled(n, 0);
  final handContrib = List<int>.filled(n, 0);
  final stacks = h.startingStacks;

  // Antes leave each seat's stack before the betting rounds. The app models
  // antes as a TableSetup.ante label, NOT as posted actions — so we must NOT
  // emit ante post actions here (that would diverge from how the app represents
  // the hand and shift the pot the prompt computes). But antes DO reduce chips
  // behind, so fold them into hand-level contribution to keep all-in detection
  // and call stack-caps correct on tournament hands.
  final antes = h.antes;
  for (var s = 0; s < n && s < antes.length; s++) {
    if (antes[s] > 0) handContrib[s] += antes[s];
  }

  // Seed preflop with blind/straddle posts (the app records these as actions
  // and the pot/pot-odds math depends on them).
  var streetIdx = 0;
  final perStreetActions = <int, List<HandAction>>{0: []};
  final perStreetBoard = <int, List<String>>{};

  void commit(int seat, int cumulativeThisStreet) {
    final inc = cumulativeThisStreet - streetContrib[seat];
    streetContrib[seat] = cumulativeThisStreet;
    handContrib[seat] += inc;
  }

  final sbSeat = ts.sbSeat, bbSeat = ts.bbSeat;
  if (ts.smallBlind > 0) {
    perStreetActions[0]!.add(HandAction(
        seat: sbSeat, type: ActionType.post, amount: ts.smallBlind));
    commit(sbSeat, ts.smallBlind);
  }
  if (ts.bigBlind > 0) {
    perStreetActions[0]!.add(HandAction(
        seat: bbSeat, type: ActionType.post, amount: ts.bigBlind));
    commit(bbSeat, ts.bigBlind);
  }
  if (ts.straddle != null && ts.straddleSeat >= 0) {
    perStreetActions[0]!.add(HandAction(
        seat: ts.straddleSeat,
        type: ActionType.postStraddle,
        amount: ts.straddle));
    commit(ts.straddleSeat, ts.straddle!);
  }

  bool aggressionThisStreet() {
    final acts = perStreetActions[streetIdx] ?? const [];
    return acts.any((a) =>
        a.type == ActionType.raise ||
        a.type == ActionType.allIn ||
        (streetIdx == 0 &&
            (a.type == ActionType.post || a.type == ActionType.postStraddle)));
  }

  int currentMax() {
    var m = 0;
    for (final c in streetContrib) {
      if (c > m) m = c;
    }
    return m;
  }

  for (final tok in h.actionTokens) {
    final t = tok.trim();
    if (t.startsWith('d dh')) continue; // hole-card deals: handled separately
    if (t.startsWith('d db ')) {
      // Board deal -> advance street.
      final cards = _splitCards(t.substring(5).trim());
      // Each board deal advances one street: preflop=0 -> flop=1 (3 cards) ->
      // turn=2 (1 card) -> river=3 (1 card). A 4th board deal means run-it-twice
      // or a multi-board variant, which the single-board PokerHand model can't
      // represent (the s.clamp(0,3) below would collapse two Streets onto the
      // river). Fail loudly rather than emit a corrupt hand; the baker filters
      // these out up front.
      streetIdx += 1;
      if (streetIdx > 3) {
        throw StateError(
            'hand has >3 board deals (run-it-twice / multi-board not supported)');
      }
      for (var s = 0; s < n; s++) {
        streetContrib[s] = 0;
      }
      perStreetActions[streetIdx] = [];
      perStreetBoard[streetIdx] = cards;
      continue;
    }
    final fold = RegExp(r'^p(\d+) f$').firstMatch(t);
    if (fold != null) {
      final seat = int.parse(fold.group(1)!) - 1;
      perStreetActions[streetIdx]!
          .add(HandAction(seat: seat, type: ActionType.fold));
      continue;
    }
    final cc = RegExp(r'^p(\d+) cc$').firstMatch(t);
    if (cc != null) {
      final seat = int.parse(cc.group(1)!) - 1;
      final max = currentMax();
      if (max > streetContrib[seat]) {
        // Call — cumulative becomes the max, capped at the seat's stack.
        final remaining = stacks[seat] - handContrib[seat];
        final want = max - streetContrib[seat];
        final pay = want > remaining ? remaining : want;
        final cumulative = streetContrib[seat] + pay;
        commit(seat, cumulative);
        perStreetActions[streetIdx]!.add(HandAction(
          seat: seat,
          type: ActionType.call,
          amount: cumulative,
          isAllIn: stacks[seat] - handContrib[seat] == 0,
        ));
      } else {
        perStreetActions[streetIdx]!
            .add(HandAction(seat: seat, type: ActionType.check));
      }
      continue;
    }
    final cbr = RegExp(r'^p(\d+) cbr (\d+)$').firstMatch(t);
    if (cbr != null) {
      final seat = int.parse(cbr.group(1)!) - 1;
      final to = int.parse(cbr.group(2)!);
      final opening = streetIdx > 0 && !aggressionThisStreet();
      commit(seat, to);
      perStreetActions[streetIdx]!.add(HandAction(
        seat: seat,
        type: ActionType.raise,
        amount: to,
        isOpeningBet: opening,
        isAllIn: stacks[seat] - handContrib[seat] == 0,
      ));
      continue;
    }
    // `pN sm ...` (show) and anything else: ignore.
  }

  final out = <StreetData>[];
  for (var s = 0; s <= streetIdx; s++) {
    final acts = perStreetActions[s];
    if (acts == null) continue;
    out.add(StreetData(
      street: _streetOrder[s.clamp(0, 3)],
      communityCards: perStreetBoard[s] ?? const [],
      actions: acts,
    ));
  }
  return out;
}

// CLI: `dart run tool/eval/phh_parser.dart <file.phh> <heroPlayer>` prints the
// resulting PokerHand JSON — a quick way to eyeball the mapping.
void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/eval/phh_parser.dart <file.phh> <heroPlayer 1-based>');
    exit(2);
  }
  final text = File(args[0]).readAsStringSync();
  final h = parsePhhText(text);
  final hero = int.parse(args[1]);
  final hand = phhToPokerHand(
    h,
    heroPlayer: hero,
    id: 'phh-cli',
    playedAt: DateTime.utc(2026, 1, 1),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(hand.toJson()));
}
