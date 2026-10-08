import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dm_models.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// 1:1 Direct Messages (singleton).
class DirectMessageService {
  DirectMessageService._internal();

  static final DirectMessageService _instance =
      DirectMessageService._internal();

  factory DirectMessageService() => _instance;

  SupabaseClient get _client => SupabaseService.instance.client;

  String? get _uid => AuthService().currentUser?.id;

  void _assertReady() {
    if (!SupabaseService.instance.isReady) {
      throw StateError(
        'Supabase hazır değil. SUPABASE_URL / SUPABASE_ANON_KEY gerekir.',
      );
    }
  }

  void _assertSignedIn() {
    _assertReady();
    if (_uid == null) {
      throw StateError('Mesajlaşmak için giriş yapmalısın.');
    }
  }

  /// Thread listesi — son mesaja göre, engellenenler hariç.
  Future<List<DmThread>> listMyThreads({int limit = 60}) async {
    _assertSignedIn();
    final uid = _uid!;
    await SupabaseService.instance.refreshBlockedUsers();

    try {
      final rows = await _client
          .from('dm_threads')
          .select(
            'id, participant_a, participant_b, created_at, updated_at, '
            'last_message_at, last_message_preview, '
            'a_profile:profiles!dm_threads_participant_a_fkey(id, username, bio, avatar_url, created_at), '
            'b_profile:profiles!dm_threads_participant_b_fkey(id, username, bio, avatar_url, created_at)',
          )
          .or('participant_a.eq.$uid,participant_b.eq.$uid')
          .order('last_message_at', ascending: false, nullsFirst: false)
          .limit(limit);

      final threads = (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => DmThread.fromRow(
              Map<String, dynamic>.from(e),
              viewerId: uid,
            ),
          )
          .where((t) {
        final other = t.otherProfile;
        return !SupabaseService.instance.isProfileBlocked(
          userId: t.otherUserId(uid),
          username: other?.username,
        );
      }).toList(growable: false);
      return threads;
    } catch (e, st) {
      debugPrint('DirectMessageService.listMyThreads (join): $e\n$st');
      // Fallback without profile embed.
      final rows = await _client
          .from('dm_threads')
          .select()
          .or('participant_a.eq.$uid,participant_b.eq.$uid')
          .order('last_message_at', ascending: false, nullsFirst: false)
          .limit(limit);

      final base = (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => DmThread.fromRow(
              Map<String, dynamic>.from(e),
              viewerId: uid,
            ),
          )
          .toList();

      final filled = <DmThread>[];
      for (final t in base) {
        final otherId = t.otherUserId(uid);
        if (SupabaseService.instance.isProfileBlocked(userId: otherId)) {
          continue;
        }
        UserProfile? other;
        try {
          final row = await _client
              .from('profiles')
              .select('id, username, bio, avatar_url, created_at')
              .eq('id', otherId)
              .maybeSingle();
          if (row != null) {
            other = UserProfile.fromRow(Map<String, dynamic>.from(row));
          }
        } catch (_) {}
        filled.add(
          DmThread(
            id: t.id,
            participantA: t.participantA,
            participantB: t.participantB,
            createdAt: t.createdAt,
            updatedAt: t.updatedAt,
            lastMessageAt: t.lastMessageAt,
            lastMessagePreview: t.lastMessagePreview,
            otherProfile: other,
          ),
        );
      }
      return filled;
    }
  }

  /// Mevcut thread’i getirir veya oluşturur.
  Future<DmThread> getOrCreateThread(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (otherUserId.isEmpty || otherUserId == uid) {
      throw ArgumentError('Geçersiz kullanıcı.');
    }
    if (SupabaseService.instance.isProfileBlocked(userId: otherUserId)) {
      throw StateError('Bu kullanıcıyla mesajlaşamazsın.');
    }

    try {
      final raw = await _rpcGetOrCreateDm(otherUserId);

      Map<String, dynamic> row;
      if (raw is Map) {
        row = Map<String, dynamic>.from(raw);
      } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
        row = Map<String, dynamic>.from(raw.first as Map);
      } else {
        throw StateError('Sohbet açılamadı. Biraz sonra tekrar dene.');
      }

      UserProfile? other;
      try {
        final p = await _client
            .from('profiles')
            .select('id, username, bio, avatar_url, created_at')
            .eq('id', otherUserId)
            .maybeSingle();
        if (p != null) {
          other = UserProfile.fromRow(Map<String, dynamic>.from(p));
        }
      } catch (_) {}

      return DmThread.fromRow(row, viewerId: uid, otherProfile: other);
    } catch (e, st) {
      debugPrint('DirectMessageService.getOrCreateThread: $e\n$st');
      throw StateError(_friendlyDmError(e));
    }
  }

  /// Prefers `get_or_create_dm_thread`; falls back to legacy `get_or_create_dm`.
  Future<dynamic> _rpcGetOrCreateDm(String otherUserId) async {
    final args = {'p_other_user_id': otherUserId};
    try {
      return await _client.rpc('get_or_create_dm_thread', params: args);
    } on PostgrestException catch (e) {
      final missing = e.code == 'PGRST202' ||
          e.message.toLowerCase().contains('could not find the function');
      if (!missing) rethrow;
      debugPrint(
        'DirectMessageService: get_or_create_dm_thread missing '
        '(${e.code}); trying get_or_create_dm. Run migration '
        'supabase/migrations/020_fix_dm_rpc.sql',
      );
      try {
        return await _client.rpc('get_or_create_dm', params: args);
      } on PostgrestException catch (e2) {
        // Older aliases may use other_user_id without the p_ prefix.
        if (e2.code == 'PGRST202' ||
            e2.message.toLowerCase().contains('could not find')) {
          return await _client.rpc(
            'get_or_create_dm',
            params: {'other_user_id': otherUserId},
          );
        }
        rethrow;
      }
    }
  }

  static String _friendlyDmError(Object e) {
    if (e is StateError) return e.message;
    if (e is ArgumentError) {
      return e.message?.toString() ?? 'Geçersiz istek.';
    }
    final text = e.toString();
    if (text.contains('PGRST202') ||
        text.contains('Could not find the function') ||
        text.contains('get_or_create_dm')) {
      return 'Mesaj şu an açılamıyor. Biraz sonra tekrar dene.';
    }
    if (text.contains('Not authenticated') ||
        text.contains('giriş') ||
        text.contains('Sign')) {
      return 'Mesajlaşmak için giriş yapmalısın.';
    }
    if (text.contains('engellen') || text.contains('blocked')) {
      return 'Bu kullanıcıyla mesajlaşamazsın.';
    }
    return 'Mesaj açılamadı. Biraz sonra tekrar dene.';
  }

  Future<List<DmMessage>> listMessages(
    String threadId, {
    int limit = 120,
  }) async {
    _assertSignedIn();
    try {
      final rows = await _client
          .from('dm_messages')
          .select(
            'id, thread_id, sender_id, body, created_at, '
            'sender:profiles!dm_messages_sender_id_fkey(id, username, bio, avatar_url, created_at)',
          )
          .eq('thread_id', threadId)
          .order('created_at', ascending: true)
          .limit(limit);

      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => DmMessage.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('DirectMessageService.listMessages (join): $e\n$st');
      final rows = await _client
          .from('dm_messages')
          .select()
          .eq('thread_id', threadId)
          .order('created_at', ascending: true)
          .limit(limit);

      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => DmMessage.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }
  }

  Future<DmMessage> sendMessage({
    required String threadId,
    required String body,
  }) async {
    _assertSignedIn();
    final uid = _uid!;
    final text = body.trim();
    if (text.isEmpty) {
      throw ArgumentError('Mesaj boş olamaz.');
    }

    final row = await _client
        .from('dm_messages')
        .insert({
          'thread_id': threadId,
          'sender_id': uid,
          'body': text,
        })
        .select()
        .single();

    return DmMessage.fromRow(Map<String, dynamic>.from(row));
  }

  /// Realtime stream — group streak pattern ile aynı.
  Stream<List<DmMessage>> watchMessages(String threadId) {
    _assertSignedIn();
    return _client
        .from('dm_messages')
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at')
        .map(
          (rows) => rows
              .map((e) => DmMessage.fromRow(Map<String, dynamic>.from(e)))
              .toList(growable: false),
        );
  }
}
