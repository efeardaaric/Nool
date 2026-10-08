import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_item.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// In-app notification center (Supabase `notifications` + optional Realtime).
class SocialNotificationService {
  SocialNotificationService._();
  static final SocialNotificationService instance =
      SocialNotificationService._();

  final _unreadCtrl = StreamController<int>.broadcast();
  RealtimeChannel? _channel;
  int _unread = 0;

  Stream<int> get unreadCountStream => _unreadCtrl.stream;
  int get unreadCount => _unread;

  SupabaseClient get _client => SupabaseService.instance.client;
  String? get _uid => AuthService().currentUser?.id;

  void _assertReady() {
    if (!SupabaseService.instance.isReady) {
      throw StateError('Supabase hazır değil.');
    }
  }

  void _assertSignedIn() {
    _assertReady();
    if (_uid == null) throw StateError('Oturum gerekli.');
  }

  Future<List<NoolNotification>> listMyNotifications({
    int limit = 60,
    bool unreadOnly = false,
  }) async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      // ignore: prefer_typing_uninitialized_variables
      late final dynamic rows;
      if (unreadOnly) {
        rows = await _client
            .from('notifications')
            .select()
            .eq('user_id', uid)
            .isFilter('read_at', null)
            .order('created_at', ascending: false)
            .limit(limit);
      } else {
        rows = await _client
            .from('notifications')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      return (rows as List<dynamic>)
          .whereType<Map>()
          .map((e) => NoolNotification.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('SocialNotificationService.list: $e\n$st');
      rethrow;
    }
  }

  Future<int> fetchUnreadCount() async {
    if (!SupabaseService.instance.isReady || _uid == null) {
      _setUnread(0);
      return 0;
    }

    try {
      final rows = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', _uid!)
          .isFilter('read_at', null);

      final count = (rows as List).length;
      _setUnread(count);
      return count;
    } catch (e, st) {
      debugPrint('SocialNotificationService.unread: $e\n$st');
      return _unread;
    }
  }

  Future<void> markRead({List<String>? ids}) async {
    _assertSignedIn();
    try {
      if (ids == null || ids.isEmpty) {
        await _client.rpc('mark_notifications_read');
      } else {
        await _client.rpc(
          'mark_notifications_read',
          params: {'p_ids': ids},
        );
      }
      await fetchUnreadCount();
    } catch (e, st) {
      debugPrint('SocialNotificationService.markRead rpc: $e\n$st');
      try {
        if (ids != null && ids.isNotEmpty) {
          await _client
              .from('notifications')
              .update({'read_at': DateTime.now().toUtc().toIso8601String()})
              .eq('user_id', _uid!)
              .inFilter('id', ids)
              .isFilter('read_at', null);
        } else {
          await _client
              .from('notifications')
              .update({'read_at': DateTime.now().toUtc().toIso8601String()})
              .eq('user_id', _uid!)
              .isFilter('read_at', null);
        }
        await fetchUnreadCount();
      } catch (e2, st2) {
        debugPrint('SocialNotificationService.markRead fallback: $e2\n$st2');
        rethrow;
      }
    }
  }

  Future<void> markOneRead(String id) => markRead(ids: [id]);

  /// Soft-start Realtime + initial unread poll. Safe if publication missing.
  Future<void> startWatching() async {
    if (!SupabaseService.instance.isReady || _uid == null) return;
    await fetchUnreadCount();
    await stopWatching();

    try {
      final uid = _uid!;
      final channel = _client.channel('nool-notifications-$uid');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) {
          _setUnread(_unread + 1);
        },
      );
      channel.subscribe();
      _channel = channel;
    } catch (e, st) {
      debugPrint('SocialNotificationService.realtime: $e\n$st');
    }
  }

  Future<void> stopWatching() async {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _client.removeChannel(ch);
      } catch (e) {
        debugPrint('SocialNotificationService.stopWatching: $e');
      }
    }
  }

  void _setUnread(int n) {
    _unread = n < 0 ? 0 : n;
    if (!_unreadCtrl.isClosed) _unreadCtrl.add(_unread);
  }
}
