// Exports ONE real recorded hand from Supabase to tool/solver/real_hand.json so
// the POC driver can solve it. Picks the most recent recorded hand that maps to
// a supported solver spot (single-raised, heads-up-to-flop, flop decision).
//
// Needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in the environment (the `hands`
// table is RLS-scoped; the service-role key reads across users — operator-only,
// run locally, never in CI). Reads best-effort player_reads for the villains.
//
// Run:  dart run tool/solver/export_one_hand.dart

import 'dart:convert';
import 'dart:io';

import 'package:tablelab/models/hand_model.dart';

import 'solver_input.dart';

Future<void> main() async {
  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || key == null) {
    stderr.writeln('Set SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY env vars '
        '(operator-only; run locally). Or paste a hand toJson() into '
        'tool/solver/real_hand.json as {"hand": {...}, "reads": []}.');
    exit(1);
  }
  final client = HttpClient();

  Future<List<dynamic>> get(String path) async {
    final req = await client.getUrl(Uri.parse('$url/rest/v1/$path'));
    req.headers.set('apikey', key);
    req.headers.set('Authorization', 'Bearer $key');
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 300) {
      throw StateError('GET $path -> ${resp.statusCode}: $body');
    }
    return jsonDecode(body) as List<dynamic>;
  }

  // Newest hands first; scan for the first solver-compatible flop spot.
  final rows = await get('hands?select=hand_data&order=played_at.desc&limit=100');
  stdout.writeln('Fetched ${rows.length} recent hands; scanning for a '
      'single-raised heads-up flop spot…');

  for (final row in rows) {
    final hd = (row as Map<String, dynamic>)['hand_data'];
    if (hd is! Map<String, dynamic>) continue;
    final PokerHand hand;
    try {
      hand = PokerHand.fromJson(hd);
    } catch (_) {
      continue;
    }
    try {
      SolverSpot.fromHand(hand); // throws UnsupportedSpot if not a clean spot
    } on UnsupportedSpot {
      continue;
    } catch (_) {
      continue;
    }

    // Best-effort reads for the villains (match by player name → playerLabel).
    final villainNames = hand.players
        .where((p) => !p.isHero)
        .map((p) => p.name)
        .toSet();
    final reads = <Map<String, dynamic>>[];
    try {
      final readRows = await get('player_reads?select=player_label,tags&user_id=eq.${hand.userId}');
      for (final r in readRows) {
        final m = r as Map<String, dynamic>;
        final label = m['player_label'] as String?;
        if (label != null && villainNames.contains(label)) {
          reads.add({'playerLabel': label, 'tags': (m['tags'] as List?)?.cast<String>() ?? []});
        }
      }
    } catch (_) {
      // reads are optional
    }

    final outFile = File('tool/solver/real_hand.json');
    outFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({'hand': hd, 'reads': reads}));
    stdout.writeln('Wrote ${outFile.path} — hand ${hand.id} '
        '(${hand.streetReached}, ${reads.length} reads). Now run '
        '`dart run tool/solver/poc.dart`.');
    client.close();
    return;
  }

  client.close();
  stderr.writeln('No single-raised heads-up flop spot found in the last 100 '
      'hands. Record one (or widen the scan) and retry.');
  exit(1);
}
