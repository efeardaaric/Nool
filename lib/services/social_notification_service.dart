import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_models.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// Squad istekleri + DM için canlı in-app bildirim akışı.
class SocialNotificationService {
  SocialNotificationService._internal();

  static final SocialNotificationService _instance =
      SocialNotificationService._internal();

  factory SocialNotificationService() => _instance;

  final _events = StreamController<SocialEvent>.broadcast();
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  RealtimeChannel? _channel;
  String? _boundUid;
  bool _started = false;

  Stream<SocialEvent> get events => _events.stream;

  SupabaseClient get _client => SupabaseService.instance.client;

  String? get _uid => AuthService().currentUser?.id;

  /// Oturum açılınca çağır; zaten açıksa no-op.
  Future<void> start() async {
    if (!SupabaseService.instance.isReady) return;
    final uid = _uid;
    if (uid == null) {
      await stop();
      return;
    }
    if (_started && _boundUid == uid) return;

    await stop();
    _boundUid = uid;
    _started = true;

    try {
      await _refreshBadgeCounts(uid);

      _channel = _client
          .channel('social-notify-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'squads',
            callback: (payload) => _onSquadInsert(payload, uid),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'squads',
            callback: (payload) => _onSquadUpdate(payload, uid),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (payload) => _onMessageInsert(payload, uid),
          )
          .subscribe();
    } catch (e, st) {
      debugPrint('SocialNotificationService.start: $e\n$st');
      _started = false;
    }
  }

  Future<void> stop() async {
    final ch = _channel;
    _channel = null;
    _started = false;
    _boundUid = null;
    if (ch != null) {
      try {
        await _client.removeChannel(ch);
      } catch (_) {}
    }
  }

  void markAllSeen() {
    unreadCount.value = 0;
  }

  void decrementUnread([int by = 1]) {
    unreadCount.value = (unreadCount.value - by).clamp(0, 9999);
  }

  Future<void> _refreshBadgeCounts(String uid) async {
    try {
      final pending = await _client
          .from('squads')
          .select('id')
          .eq('receiver_id', uid)
          .eq('status', 'pending');
      unreadCount.value = (pending as List).length;
    } catch (e) {
      debugPrint('SocialNotificationService._refreshBadgeCounts: $e');
    }
  }

  void _emit(SocialEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
      unreadCount.value = unreadCount.value + 1;
    }
  }

  Future<void> _onSquadInsert(PostgresChangePayload payload, String uid) async {
    final row = payload.newRecord;
    final receiverId = row['receiver_id']?.toString();
    final senderId = row['sender_id']?.toString();
    final status = row['status']?.toString() ?? 'pending';
    if (receiverId != uid || status != 'pending' || senderId == null) return;

    final username = await _usernameOf(senderId);
    _emit(
      SocialEvent(
        id: 'squad-req-${row['id']}',
        type: SocialEventType.squadRequest,
        title: 'Yeni squad isteği',
        body: '$username sana squad attı.',
        createdAt: DateTime.now().toUtc(),
        relatedUserId: senderId,
        relatedUsername: username,
        requestId: row['id']?.toString(),
      ),
    );
  }

  Future<void> _onSquadUpdate(PostgresChangePayload payload, String uid) async {
    final row = payload.newRecord;
    final old = payload.oldRecord;
    final status = row['status']?.toString();
    final oldStatus = old['status']?.toString();
    if (status != 'accepted' || oldStatus == 'accepted') return;

    final senderId = row['sender_id']?.toString();
    final receiverId = row['receiver_id']?.toString();
    // Kabul bildirimi gönderene gider.
    if (senderId != uid || receiverId == null) return;

    final username = await _usernameOf(receiverId);
    _emit(
      SocialEvent(
        id: 'squad-ok-${row['id']}-${DateTime.now().millisecondsSinceEpoch}',
        type: SocialEventType.squadAccepted,
        title: 'Squad kabul edildi',
        body: '$username isteğini kabul etti. Mesajlaşabilirsiniz.',
        createdAt: DateTime.now().toUtc(),
        relatedUserId: receiverId,
        relatedUsername: username,
        requestId: row['id']?.toString(),
      ),
    );
  }

  Future<void> _onMessageInsert(
    PostgresChangePayload payload,
    String uid,
  ) async {
    final row = payload.newRecord;
    final senderId = row['sender_id']?.toString();
    final conversationId = row['conversation_id']?.toString();
    if (senderId == null || senderId == uid || conversationId == null) return;

    try {
      final conv = await _client
          .from('conversations')
          .select('id, participant_low, participant_high')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv == null) return;
      final low = conv['participant_low']?.toString();
      final high = conv['participant_high']?.toString();
      if (uid != low && uid != high) return;
    } catch (_) {
      return;
    }

    final username = await _usernameOf(senderId);
    final body = (row['body'] as String?) ?? '';
    final preview = body.length > 80 ? '${body.substring(0, 80)}…' : body;

    _emit(
      SocialEvent(
        id: 'msg-${row['id']}',
        type: SocialEventType.newMessage,
        title: 'Yeni mesaj',
        body: '$username: $preview',
        createdAt: DateTime.now().toUtc(),
        relatedUserId: senderId,
        relatedUsername: username,
        conversationId: conversationId,
      ),
    );
  }

  Future<String> _usernameOf(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle();
      final name = row?['username'] as String?;
      if (name == null || name.isEmpty) return '@anon';
      return name.startsWith('@') ? name : '@$name';
    } catch (_) {
      return '@anon';
    }
  }
}
