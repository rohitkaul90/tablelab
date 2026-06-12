import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hand_model.dart';
import 'supabase_retry.dart';

class HandService {
  SupabaseClient get _client => Supabase.instance.client;

  String get _uid {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    return uid;
  }

  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<List<PokerHand>> fetchHands() => withSupabaseRetry(() async {
    final rows = await _client
        .from('hands')
        .select()
        .eq('user_id', _uid)
        .order('played_at', ascending: false);
    return (rows as List).map((row) {
      final data = Map<String, dynamic>.from(row['hand_data'] as Map);
      data['id'] = row['id'] as String;
      data['userId'] = row['user_id'] as String;
      if (row['session_id'] != null) {
        data['sessionId'] = row['session_id'] as String;
      }
      data['playedAt'] = row['played_at'] as String;
      return PokerHand.fromJson(data);
    }).toList();
  });

  Future<PokerHand> saveHand({
    required TableSetup tableSetup,
    required List<HandPlayer> players,
    required List<StreetData> streets,
    String? sessionId,
    String? notes,
    String? tournamentStage,
    bool isTournament = false,
    bool isQuickEntry = false,
  }) => withSupabaseRetry(() async {
    final id = _uuid();
    final now = DateTime.now();
    final hand = PokerHand(
      id: id,
      userId: _uid,
      sessionId: sessionId,
      playedAt: now,
      tableSetup: tableSetup,
      players: players,
      streets: streets,
      notes: notes,
      tournamentStage: tournamentStage,
      isTournament: isTournament,
      isQuickEntry: isQuickEntry,
    );
    await _client.from('hands').insert({
      'id': id,
      'user_id': _uid,
      if (sessionId != null) 'session_id': sessionId,
      'played_at': now.toIso8601String(),
      'hand_data': hand.toJson(),
    });
    return hand;
  });

  Future<void> updateHandSession(String handId, String? sessionId) =>
      withSupabaseRetry(() async {
        await _client
            .from('hands')
            .update({'session_id': sessionId})
            .eq('id', handId)
            .eq('user_id', _uid);
      });

  Future<void> deleteHand(String handId) => withSupabaseRetry(() async {
    await _client
        .from('hands')
        .delete()
        .eq('id', handId)
        .eq('user_id', _uid);
  });
}
