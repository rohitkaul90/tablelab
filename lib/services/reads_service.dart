import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player_read.dart';
import 'supabase_retry.dart';

class ReadsService {
  final _client = Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  // One-shot fetch (no Realtime websocket). Realtime `.stream()` was dropped
  // because a flaky channel surfaced RealtimeSubscribeException(channelError)
  // to users; the list is kept fresh via explicit ref.invalidate after writes.
  Future<List<PlayerRead>> fetchReads() => withSupabaseRetry(() async {
    final uid = _uid;
    if (uid == null) return <PlayerRead>[];
    final rows = await _client
        .from('player_reads')
        .select()
        .eq('user_id', uid)
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => PlayerRead.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  Future<List<PlayerReadNote>> fetchNotes(String readId) => withSupabaseRetry(() async {
    final data = await _client
        .from('player_read_notes')
        .select()
        .eq('read_id', readId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => PlayerReadNote.fromJson(e as Map<String, dynamic>)).toList();
  });

  Future<PlayerRead> createRead({
    required String playerLabel,
    required List<String> tags,
  }) {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    return withSupabaseRetry(() async {
      final data = await _client.from('player_reads').insert({
        'user_id': uid,
        'player_label': playerLabel,
        'tags': tags,
      }).select().single();
      return PlayerRead.fromJson(data);
    });
  }

  Future<void> updateRead(String readId, {String? playerLabel, List<String>? tags}) {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (playerLabel != null) updates['player_label'] = playerLabel;
    if (tags != null) updates['tags'] = tags;
    return withSupabaseRetry(() => _client
        .from('player_reads')
        .update(updates)
        .eq('id', readId)
        .eq('user_id', uid));
  }

  Future<void> updateNote(String noteId, {
    String? noteText,
    String? position,
    String? action,
    String? sizing,
    String? street,
    String? cardsShown,
  }) => withSupabaseRetry(() => _client.from('player_read_notes').update({
        'note_text': (noteText?.isEmpty ?? true) ? null : noteText,
        'position': position,
        'action': action,
        'sizing': (sizing?.isEmpty ?? true) ? null : sizing,
        'street': street,
        'cards_shown': (cardsShown?.isEmpty ?? true) ? null : cardsShown,
      }).eq('id', noteId));

  Future<void> addNote(String readId, {
    String? noteText,
    String? position,
    String? action,
    String? sizing,
    String? street,
    String? cardsShown,
  }) => withSupabaseRetry(() async {
    await _client.from('player_read_notes').insert({
      'read_id': readId,
      'note_text': noteText?.isEmpty == true ? null : noteText,
      'position': position,
      'action': action,
      'sizing': sizing?.isEmpty == true ? null : sizing,
      'street': street,
      'cards_shown': cardsShown?.isEmpty == true ? null : cardsShown,
    });
    await _client.from('player_reads').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', readId);
  });

  Future<void> deleteNote(String noteId) =>
      withSupabaseRetry(() => _client.from('player_read_notes').delete().eq('id', noteId));

  Future<void> deleteRead(String readId) =>
      withSupabaseRetry(() => _client.from('player_reads').delete().eq('id', readId));
}
