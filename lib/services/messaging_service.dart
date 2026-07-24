import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_models.dart';
import 'auth_service.dart';
import 'profile_service.dart';
import 'supabase_service.dart';

/// 1:1 DM — listele, aç, gönder, realtime dinle.
class MessagingService {
  MessagingService._internal();

  static final MessagingService _instance = MessagingService._internal();

  factory MessagingService() => _instance;

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

  /// Inbox — conversation listesi.
  Future<List<ConversationPreview>> listConversations() async {
    _assertSignedIn();
    try {
      final rows = await _client.rpc('list_my_conversations');
      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => ConversationPreview.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('MessagingService.listConversations: $e\n$st');
      rethrow;
    }
  }

  /// Squad arkadaşla DM aç / mevcut konuşmayı getir.
  Future<ConversationPreview> openDmWith({
    required String otherUserId,
    String? otherUsername,
    String? otherAvatarUrl,
  }) async {
    _assertSignedIn();
    if (await ProfileService().areUsersBlocked(otherUserId)) {
      throw StateError('Bu kullanıcıyla mesajlaşma engellendi.');
    }
    try {
      final row = await _client.rpc(
        'get_or_create_dm',
        params: {'p_other_user_id': otherUserId},
      );
      final map = Map<String, dynamic>.from(row as Map);
      final uid = _uid!;
      final low = map['participant_low']?.toString();
      final high = map['participant_high']?.toString();
      final otherId = low == uid ? high : low;

      String username = otherUsername ?? '@anon';
      String? avatar = otherAvatarUrl;
      if (otherId != null &&
          (otherUsername == null || otherUsername.isEmpty)) {
        final p = await _client
            .from('profiles')
            .select('username, avatar_url')
            .eq('id', otherId)
            .maybeSingle();
        if (p != null) {
          username = (p['username'] as String?) ?? username;
          avatar = p['avatar_url'] as String?;
        }
      }

      return ConversationPreview(
        conversationId: map['id'].toString(),
        otherUserId: otherId ?? otherUserId,
        otherUsername: username,
        otherAvatarUrl: avatar,
        lastMessageAt: map['last_message_at'] == null
            ? null
            : DateTime.tryParse(map['last_message_at'].toString())?.toUtc(),
        lastMessagePreview:
            (map['last_message_preview'] as String?) ?? '',
        createdAt: map['created_at'] == null
            ? null
            : DateTime.tryParse(map['created_at'].toString())?.toUtc(),
      );
    } catch (e, st) {
      debugPrint('MessagingService.openDmWith: $e\n$st');
      rethrow;
    }
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
  }) async {
    _assertSignedIn();
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Boş mesaj gönderilemez.');
    }
    if (trimmed.length > 2000) {
      throw ArgumentError('Mesaj en fazla 2000 karakter olabilir.');
    }

    try {
      final row = await _client.rpc(
        'send_dm',
        params: {
          'p_conversation_id': conversationId,
          'p_body': trimmed,
        },
      );
      return ChatMessage.fromRow(Map<String, dynamic>.from(row as Map));
    } catch (e, st) {
      debugPrint('MessagingService.sendMessage: $e\n$st');
      rethrow;
    }
  }

  /// Konuşma mesajları — Realtime stream (eskiden yeniye).
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    _assertSignedIn();
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map(
          (rows) => rows
              .map(
                (row) => ChatMessage.fromRow(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false),
        );
  }

  /// Karşı tarafın okunmamış mesajlarını işaretle.
  Future<void> markRead(String conversationId) async {
    _assertSignedIn();
    final uid = _uid!;
    try {
      await _client
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', conversationId)
          .neq('sender_id', uid)
          .isFilter('read_at', null);
    } catch (e, st) {
      debugPrint('MessagingService.markRead: $e\n$st');
    }
  }

  /// Inbox yenileme sinyali — conversations / messages / squads değişince.
  Stream<void> watchInboxChanges() {
    _assertSignedIn();
    final uid = _uid!;
    final controller = StreamController<void>.broadcast();
    RealtimeChannel? channel;

    void emit() {
      if (!controller.isClosed) controller.add(null);
    }

    channel = _client
        .channel('inbox-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => emit(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => emit(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'squads',
          callback: (_) => emit(),
        )
        .subscribe();

    controller.onCancel = () async {
      final ch = channel;
      channel = null;
      if (ch != null) {
        await _client.removeChannel(ch);
      }
    };

    return controller.stream;
  }
}
