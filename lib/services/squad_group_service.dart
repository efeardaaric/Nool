import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/squad_group_models.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// Squad Circles + Group Drops + Kaos Ateşi (singleton).
class SquadGroupService {
  SquadGroupService._internal();

  static final SquadGroupService _instance = SquadGroupService._internal();

  factory SquadGroupService() => _instance;

  static const _uuid = Uuid();

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
      throw StateError('Kadro işlemi için giriş yapmalısın.');
    }
  }

  /// Yeni kadro oluşturur: grup + üyeler (me dahil) + streak = 0.
  Future<SquadGroup> createSquadCircle({
    required String groupName,
    required List<String> memberUserIds,
  }) async {
    _assertSignedIn();
    final uid = _uid!;
    final name = groupName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Grup adı boş olamaz.');
    }

    final memberIds = <String>{
      uid,
      ...memberUserIds.where((id) => id.isNotEmpty)
    };

    // Client-side id — INSERT RETURNING RLS select henüz üyelik yokken başarısız olur.
    final groupId = _uuid.v4();
    final now = DateTime.now().toUtc();

    try {
      await _client.from('squad_groups').insert({
        'id': groupId,
        'name': name,
        'created_by': uid,
      });

      // RLS: önce kendini ekle (boş grup), sonra diğerleri.
      await _client.from('squad_group_members').insert({
        'group_id': groupId,
        'user_id': uid,
      });

      final others = memberIds.where((id) => id != uid).toList();
      if (others.isNotEmpty) {
        await _client.from('squad_group_members').insert(
              others.map((id) => {'group_id': groupId, 'user_id': id}).toList(),
            );
      }

      await _client.from('group_streaks').insert({
        'group_id': groupId,
        'current_streak': 0,
      });

      return SquadGroup(
        id: groupId,
        name: name,
        createdBy: uid,
        createdAt: now,
        memberCount: memberIds.length,
        streak: GroupStreak(
          id: groupId,
          groupId: groupId,
          currentStreak: 0,
        ),
      );
    } catch (e, st) {
      debugPrint('SquadGroupService.createSquadCircle: $e\n$st');
      rethrow;
    }
  }

  /// Videoyu `group-drops/{groupId}/{uuid}.mp4` yükler, satır ekler (trigger streak günceller).
  Future<GroupDrop> dropVideoToGroup({
    required String groupId,
    required File videoFile,
    required String caption,
  }) async {
    _assertSignedIn();
    final uid = _uid!;

    if (!await videoFile.exists()) {
      throw StateError('Video dosyası bulunamadı: ${videoFile.path}');
    }

    final id = _uuid.v4();
    final ext = _extensionOf(videoFile.path);
    final objectPath = '$groupId/$id$ext';

    try {
      await _client.storage.from(SupabaseConfig.groupDropsBucket).upload(
            objectPath,
            videoFile,
            fileOptions: FileOptions(
              contentType: _contentTypeFor(ext),
              upsert: false,
            ),
          );

      final videoUrl = _client.storage
          .from(SupabaseConfig.groupDropsBucket)
          .getPublicUrl(objectPath);

      await _client.from('group_drops').insert({
        'id': id,
        'group_id': groupId,
        'video_url': videoUrl,
        'caption': caption.trim(),
        'sender_id': uid,
        'storage_path': objectPath,
      });

      try {
        final row = await _client
            .from('group_drops')
            .select(
              'id, group_id, video_url, caption, sender_id, storage_path, created_at, '
              'sender:profiles!group_drops_sender_id_fkey(username, avatar_url)',
            )
            .eq('id', id)
            .single();
        return GroupDrop.fromRow(Map<String, dynamic>.from(row));
      } catch (_) {
        return GroupDrop(
          id: id,
          groupId: groupId,
          videoUrl: videoUrl,
          caption: caption.trim(),
          senderId: uid,
          storagePath: objectPath,
          createdAt: DateTime.now().toUtc(),
        );
      }
    } catch (e, st) {
      debugPrint('SquadGroupService.dropVideoToGroup: $e\n$st');
      rethrow;
    }
  }

  /// Engellenen göndericilerin drop’larını eler (id + username, vibe feed ile aynı).
  List<GroupDrop> filterBlockedDrops(List<GroupDrop> drops) {
    final sb = SupabaseService.instance;
    if (sb.blockedUserIds.isEmpty && sb.blockedUsernames.isEmpty) {
      return drops;
    }
    return drops
        .where(
          (d) => !sb.isProfileBlocked(
            userId: d.senderId,
            username: d.senderUsername,
          ),
        )
        .toList(growable: false);
  }

  /// Son 24 saatteki aktif drop’lar (yeniden eskiye), engellenenler hariç.
  Future<List<GroupDrop>> getGroupFeed(String groupId) async {
    _assertSignedIn();
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();

    // Yerel + DB engel listesini tazele (gelecek yüklemeler temiz kalsın).
    await SupabaseService.instance.refreshBlockedUsers();

    try {
      final rows = await _client
          .from('group_drops')
          .select(
            'id, group_id, video_url, caption, sender_id, storage_path, created_at, '
            'sender:profiles!group_drops_sender_id_fkey(username, avatar_url)',
          )
          .eq('group_id', groupId)
          .gte('created_at', since)
          .order('created_at', ascending: false);

      final drops = (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => GroupDrop.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      return filterBlockedDrops(drops);
    } catch (e, st) {
      debugPrint('SquadGroupService.getGroupFeed: $e\n$st');
      final rows = await _client
          .from('group_drops')
          .select()
          .eq('group_id', groupId)
          .gte('created_at', since)
          .order('created_at', ascending: false);

      final drops = (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => GroupDrop.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      return filterBlockedDrops(drops);
    }
  }

  Future<GroupStreak?> getGroupStreak(String groupId) async {
    _assertSignedIn();
    try {
      final row = await _client
          .from('group_streaks')
          .select()
          .eq('group_id', groupId)
          .maybeSingle();
      if (row == null) return null;
      return GroupStreak.fromRow(Map<String, dynamic>.from(row));
    } catch (e, st) {
      debugPrint('SquadGroupService.getGroupStreak: $e\n$st');
      rethrow;
    }
  }

  /// Realtime streak değişiklikleri (opsiyonel UI dinleme).
  Stream<GroupStreak?> watchGroupStreak(String groupId) {
    _assertSignedIn();
    return _client
        .from('group_streaks')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .map((rows) {
          if (rows.isEmpty) return null;
          return GroupStreak.fromRow(Map<String, dynamic>.from(rows.first));
        });
  }

  /// Üye olunan kadrolar + `group_streaks` (id, name, current_streak, expiry).
  Future<List<SquadGroup>> listMyGroups() async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      final memberRows = await _client
          .from('squad_group_members')
          .select('group_id')
          .eq('user_id', uid);

      final groupIds = (memberRows as List<dynamic>)
          .map((e) => (e as Map)['group_id']?.toString())
          .whereType<String>()
          .toList();

      if (groupIds.isEmpty) return const [];

      final rows = await _client
          .from('squad_groups')
          .select(
            'id, name, created_by, created_at, '
            'group_streaks(id, group_id, current_streak, last_drop_at, streak_expiry_at), '
            'squad_group_members(id)',
          )
          .inFilter('id', groupIds)
          .order('created_at', ascending: false);

      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => SquadGroup.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('SquadGroupService.listMyGroups: $e\n$st');
      rethrow;
    }
  }

  /// `listMyGroups` alias — streak alanları join ile gelir; eksikse tek tek doldurur.
  Future<List<SquadGroup>> listMyGroupsWithStreaks() async {
    final groups = await listMyGroups();
    if (groups.isEmpty) return groups;

    final needsFetch = groups.any((g) => g.streak == null);
    if (!needsFetch) return groups;

    final filled = <SquadGroup>[];
    for (final g in groups) {
      if (g.streak != null) {
        filled.add(g);
        continue;
      }
      try {
        final streak = await getGroupStreak(g.id);
        filled.add(g.copyWith(streak: streak));
      } catch (_) {
        filled.add(g);
      }
    }
    return filled;
  }

  Future<List<GroupMessage>> getGroupMessages(
    String groupId, {
    int limit = 80,
  }) async {
    _assertSignedIn();
    try {
      final rows = await _client
          .from('group_messages')
          .select(
            'id, group_id, sender_id, body, created_at, '
            'sender:profiles!group_messages_sender_id_fkey(id,username,bio,avatar_url,created_at,email_domain,university_id)',
          )
          .eq('group_id', groupId)
          .order('created_at', ascending: true)
          .limit(limit);

      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => GroupMessage.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('SquadGroupService.getGroupMessages: $e\n$st');
      final rows = await _client
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: true)
          .limit(limit);

      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => GroupMessage.fromRow(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }
  }

  /// Kadro sahibi mi? (migration öncesi `created_by` yoksa false).
  Future<bool> isGroupOwner(String groupId) async {
    _assertSignedIn();
    final uid = _uid!;
    try {
      final row = await _client
          .from('squad_groups')
          .select('created_by')
          .eq('id', groupId)
          .maybeSingle();
      if (row == null) return false;
      return row['created_by']?.toString() == uid;
    } catch (e, st) {
      debugPrint('SquadGroupService.isGroupOwner: $e\n$st');
      return false;
    }
  }

  /// Owner-only hard delete — CASCADE members / messages / drops / streaks.
  Future<void> deleteSquadCircle(String groupId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (groupId.isEmpty) {
      throw ArgumentError('groupId boş olamaz.');
    }

    try {
      final row = await _client
          .from('squad_groups')
          .select('id, created_by')
          .eq('id', groupId)
          .maybeSingle();
      if (row == null) {
        throw StateError('Kadro bulunamadı.');
      }
      if (row['created_by']?.toString() != uid) {
        throw StateError('Yalnızca kadro kurucusu silebilir.');
      }

      await _client.from('squad_groups').delete().eq('id', groupId);
    } catch (e, st) {
      debugPrint('SquadGroupService.deleteSquadCircle: $e\n$st');
      rethrow;
    }
  }

  Future<GroupMessage> sendGroupMessage({
    required String groupId,
    required String body,
  }) async {
    _assertSignedIn();
    final uid = _uid!;
    final text = body.trim();
    if (text.isEmpty) {
      throw ArgumentError('Mesaj boş olamaz.');
    }

    final row = await _client
        .from('group_messages')
        .insert({
          'group_id': groupId,
          'sender_id': uid,
          'body': text,
        })
        .select()
        .single();

    return GroupMessage.fromRow(Map<String, dynamic>.from(row));
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.mp4';
    return path.substring(dot).toLowerCase();
  }

  static String _contentTypeFor(String ext) {
    switch (ext) {
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }
}

extension SquadGroupCopy on SquadGroup {
  SquadGroup copyWith({
    String? createdBy,
    int? memberCount,
    GroupStreak? streak,
  }) {
    return SquadGroup(
      id: id,
      name: name,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt,
      memberCount: memberCount ?? this.memberCount,
      streak: streak ?? this.streak,
    );
  }
}
