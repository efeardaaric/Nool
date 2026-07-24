import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/squad_models.dart';
import '../models/user_profile.dart';
import '../models/vibe_post.dart';
import 'auth_service.dart';
import 'onboarding_service.dart';
import 'supabase_service.dart';

/// Profil, kişisel videolar ve Squad ilişkileri (singleton).
class ProfileService {
  ProfileService._internal();

  static final ProfileService _instance = ProfileService._internal();

  factory ProfileService() => _instance;

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
      throw StateError('Profil işlemi için giriş yapmalısın.');
    }
  }

  /// Aktif kullanıcının profil satırı.
  Future<UserProfile?> fetchMyProfile() async {
    _assertReady();
    final uid = _uid;
    if (uid == null) return null;

    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      return UserProfile.fromRow(Map<String, dynamic>.from(row));
    } catch (e, st) {
      debugPrint('ProfileService.fetchMyProfile: $e\n$st');
      rethrow;
    }
  }

  /// Başka kullanıcının profili (id veya username).
  Future<UserProfile?> fetchProfile({
    String? userId,
    String? username,
  }) async {
    _assertReady();

    try {
      if (userId != null && userId.isNotEmpty) {
        final row = await _client
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
        if (row != null) {
          return UserProfile.fromRow(Map<String, dynamic>.from(row));
        }
      }

      if (username != null && username.trim().isNotEmpty) {
        final raw = username.trim();
        final candidates = <String>{
          raw,
          raw.startsWith('@') ? raw.substring(1) : '@$raw',
        };
        for (final name in candidates) {
          final row = await _client
              .from('profiles')
              .select()
              .eq('username', name)
              .maybeSingle();
          if (row != null) {
            return UserProfile.fromRow(Map<String, dynamic>.from(row));
          }
        }
      }
      return null;
    } catch (e, st) {
      debugPrint('ProfileService.fetchProfile: $e\n$st');
      rethrow;
    }
  }

  static const _videoSelect =
      'id, video_url, username, caption, subtitle, track_label, '
      'vibe_count, comment_count, created_at, device_id';

  String get _ttlSinceIso => DateTime.now()
      .toUtc()
      .subtract(SupabaseConfig.videoTtl)
      .toIso8601String();

  /// device_id + username sonuçlarını birleştirip id’ye göre tekilleştirir.
  /// Sunucu RLS + created_at filtresi + istemci TTL ile 24s penceresi korunur.
  Future<List<dynamic>> _fetchMergedVideoRows({
    String? deviceId,
    Set<String> usernames = const {},
  }) async {
    final byId = <String, Map<String, dynamic>>{};
    final since = _ttlSinceIso;

    void ingest(List<dynamic> rows) {
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final id = '${map['id'] ?? ''}';
        if (id.isEmpty) continue;
        byId[id] = map;
      }
    }

    if (deviceId != null && deviceId.isNotEmpty) {
      final rows = await _client
          .from('videos')
          .select(_videoSelect)
          .eq('device_id', deviceId)
          .gte('created_at', since)
          .order('created_at', ascending: false);
      ingest(List<dynamic>.from(rows as List));
    }

    if (usernames.isNotEmpty) {
      final rows = await _client
          .from('videos')
          .select(_videoSelect)
          .inFilter('username', usernames.toList())
          .gte('created_at', since)
          .order('created_at', ascending: false);
      ingest(List<dynamic>.from(rows as List));
    }

    final merged = byId.values.toList();
    merged.sort((a, b) {
      final aAt = DateTime.tryParse('${a['created_at']}') ?? DateTime(1970);
      final bAt = DateTime.tryParse('${b['created_at']}') ?? DateTime(1970);
      return bAt.compareTo(aAt);
    });
    return merged;
  }

  /// Kullanıcının aktif (TTL) videoları — username / device eşleşmesi.
  Future<List<VibePost>> getUploadedVideosForUser({
    String? username,
    String? deviceId,
  }) async {
    _assertReady();

    try {
      final usernames = <String>{};
      if (username != null && username.trim().isNotEmpty) {
        final raw = username.trim();
        usernames.add(raw);
        usernames.add(raw.startsWith('@') ? raw.substring(1) : '@$raw');
      }

      final rows = await _fetchMergedVideoRows(
        deviceId: deviceId,
        usernames: usernames,
      );
      return _mapVideoRows(rows);
    } catch (e, st) {
      debugPrint('ProfileService.getUploadedVideosForUser: $e\n$st');
      rethrow;
    }
  }

  /// Aktif videoların vibe toplamı.
  Future<int> getTotalVibesForUser({
    String? username,
    String? deviceId,
  }) async {
    final posts = await getUploadedVideosForUser(
      username: username,
      deviceId: deviceId,
    );
    return posts.fold<int>(0, (sum, p) => sum + p.vibeCount);
  }

  List<VibePost> _mapVideoRows(List<dynamic> rows) {
    final posts = <VibePost>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      map.putIfAbsent('distance_m', () => null);
      map.putIfAbsent('score', () => null);
      final post = VibePost.fromRpc(map);
      posts.add(
        VibePost(
          id: post.id,
          videoUrl: post.videoUrl,
          username: post.username,
          caption: post.caption,
          distanceLabel: 'drop',
          subtitle: post.subtitle,
          trackLabel: post.trackLabel,
          vibeCountLabel: post.vibeCountLabel,
          commentCountLabel: post.commentCountLabel,
          avatarColor: post.avatarColor,
          vibeCount: post.vibeCount,
          commentCount: post.commentCount,
          createdAt: post.createdAt,
        ),
      );
    }
    return SupabaseService.instance.filterFreshVideos(posts);
  }

  /// İki kullanıcı arasındaki squad satırı (request id için).
  Future<SquadEdge?> findSquadWith(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (otherUserId == uid) return null;

    try {
      final rows = await _client
          .from('squads')
          .select()
          .or(
            'and(sender_id.eq.$uid,receiver_id.eq.$otherUserId),'
            'and(sender_id.eq.$otherUserId,receiver_id.eq.$uid)',
          )
          .limit(1);

      if (rows.isEmpty) return null;
      return SquadEdge.fromRow(
        Map<String, dynamic>.from(rows.first as Map),
        viewerId: uid,
      );
    } catch (e, st) {
      debugPrint('ProfileService.findSquadWith: $e\n$st');
      rethrow;
    }
  }

  /// Profil güncelle — opsiyonel avatar yükle / kaldır.
  Future<UserProfile> updateProfile({
    required String username,
    required String bio,
    String? avatarPath,
    bool removeAvatar = false,
  }) async {
    _assertSignedIn();
    final uid = _uid!;

    final trimmedUser = username.trim();
    final trimmedBio = bio.trim();
    if (trimmedUser.isEmpty) {
      throw ArgumentError('Kullanıcı adı boş olamaz.');
    }
    if (trimmedBio.length > 150) {
      throw ArgumentError('Bio en fazla 150 karakter olabilir.');
    }
    if (removeAvatar && avatarPath != null && avatarPath.isNotEmpty) {
      throw ArgumentError('Avatar yükleme ve kaldırma aynı anda olamaz.');
    }

    try {
      String? avatarUrl;
      var clearAvatar = false;

      if (removeAvatar) {
        await _deleteOwnAvatars(uid);
        clearAvatar = true;
      } else if (avatarPath != null && avatarPath.isNotEmpty) {
        avatarUrl = await _uploadAvatar(uid: uid, localPath: avatarPath);
      }

      final payload = <String, dynamic>{
        'username': trimmedUser,
        'bio': trimmedBio,
        if (clearAvatar) 'avatar_url': null,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

      final row = await _client
          .from('profiles')
          .update(payload)
          .eq('id', uid)
          .select()
          .single();

      // Yerel onboarding lakabını senkron tut.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', trimmedUser.startsWith('@')
          ? trimmedUser
          : '@$trimmedUser');

      return UserProfile.fromRow(Map<String, dynamic>.from(row));
    } catch (e, st) {
      debugPrint('ProfileService.updateProfile: $e\n$st');
      rethrow;
    }
  }

  Future<String> _uploadAvatar({
    required String uid,
    required String localPath,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Avatar dosyası bulunamadı: $localPath');
    }

    final ext = _extensionOf(localPath);
    final objectPath = '$uid/${_uuid.v4()}$ext';

    await _client.storage.from(SupabaseConfig.avatarsBucket).upload(
          objectPath,
          file,
          fileOptions: FileOptions(
            contentType: _imageContentType(ext),
            upsert: true,
          ),
        );

    return _client.storage
        .from(SupabaseConfig.avatarsBucket)
        .getPublicUrl(objectPath);
  }

  /// Kullanıcının `avatars/{uid}/` altındaki dosyalarını siler.
  Future<void> _deleteOwnAvatars(String uid) async {
    try {
      final listed = await _client.storage
          .from(SupabaseConfig.avatarsBucket)
          .list(path: uid);
      if (listed.isEmpty) return;
      final paths = listed
          .map((f) => '$uid/${f.name}')
          .where((p) => p.length > uid.length + 1)
          .toList(growable: false);
      if (paths.isEmpty) return;
      await _client.storage.from(SupabaseConfig.avatarsBucket).remove(paths);
    } catch (e, st) {
      debugPrint('ProfileService._deleteOwnAvatars: $e\n$st');
      // Profil URL temizliği yine de devam etsin.
    }
  }

  /// GDPR: profiles DELETE → SQL tetikleyici auth.users siler; oturum temizlenir.
  Future<void> deleteAccount() async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      // Avatar storage orphan’larını mümkün olduğunca önce temizle.
      await _deleteOwnAvatars(uid);

      try {
        await _client.rpc('delete_own_account');
      } catch (e) {
        debugPrint(
          'ProfileService.deleteAccount rpc fallback → profiles.delete: $e',
        );
        await _client.from('profiles').delete().eq('id', uid);
      }

      await AuthService().signOut();
    } catch (e, st) {
      debugPrint('ProfileService.deleteAccount: $e\n$st');
      // Auth zaten silinmiş olabilir — yine de yerel oturumu temizle.
      try {
        await AuthService().signOut();
      } catch (_) {}
      rethrow;
    }
  }

  /// Aktif kullanıcının yüklediği videolar (device_id ve/veya username).
  Future<List<VibePost>> getMyUploadedVideos() async {
    _assertReady();

    try {
      final deviceId = await OnboardingService.getDeviceId();
      final profile = await fetchMyProfile();
      final localUsername = await OnboardingService.getUsername();

      final usernames = <String>{
        if (profile != null) profile.username,
        if (profile != null && !profile.username.startsWith('@'))
          '@${profile.username}',
        if (profile != null && profile.username.startsWith('@'))
          profile.username.substring(1),
        if (localUsername != null) localUsername,
        if (localUsername != null && !localUsername.startsWith('@'))
          '@$localUsername',
      };

      final rows = await _fetchMergedVideoRows(
        deviceId: deviceId,
        usernames: usernames,
      );

      final posts = <VibePost>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        map.putIfAbsent('distance_m', () => null);
        map.putIfAbsent('score', () => null);
        final post = VibePost.fromRpc(map);
        posts.add(
          VibePost(
            id: post.id,
            videoUrl: post.videoUrl,
            username: post.username,
            caption: post.caption,
            distanceLabel: 'senin drop',
            subtitle: post.subtitle,
            trackLabel: post.trackLabel,
            vibeCountLabel: post.vibeCountLabel,
            commentCountLabel: post.commentCountLabel,
            avatarColor: post.avatarColor,
            vibeCount: post.vibeCount,
            commentCount: post.commentCount,
            createdAt: post.createdAt,
          ),
        );
      }

      return SupabaseService.instance.filterFreshVideos(posts);
    } catch (e, st) {
      debugPrint('ProfileService.getMyUploadedVideos: $e\n$st');
      rethrow;
    }
  }

  /// Ben ↔ [otherUserId] engelli mi? (her iki yön).
  Future<bool> areUsersBlocked(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (otherUserId == uid) return false;

    try {
      final result = await _client.rpc(
        'are_users_blocked',
        params: {'p_other_user_id': otherUserId},
      );
      return result == true;
    } catch (e, st) {
      debugPrint('ProfileService.areUsersBlocked rpc fallback → select: $e\n$st');
      try {
        final rows = await _client
            .from('blocks')
            .select('id')
            .or(
              'and(blocker_id.eq.$uid,blocked_id.eq.$otherUserId),'
              'and(blocker_id.eq.$otherUserId,blocked_id.eq.$uid)',
            )
            .limit(1);
        return (rows as List).isNotEmpty;
      } catch (e2, st2) {
        debugPrint('ProfileService.areUsersBlocked: $e2\n$st2');
        rethrow;
      }
    }
  }

  /// Yalnızca benim engellediğim kullanıcı mı?
  Future<bool> haveIBlocked(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (otherUserId == uid) return false;

    try {
      final row = await _client
          .from('blocks')
          .select('id')
          .eq('blocker_id', uid)
          .eq('blocked_id', otherUserId)
          .maybeSingle();
      return row != null;
    } catch (e, st) {
      debugPrint('ProfileService.haveIBlocked: $e\n$st');
      rethrow;
    }
  }

  Future<void> blockUser(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (otherUserId == uid) {
      throw ArgumentError('Kendini engelleyemezsin.');
    }

    try {
      try {
        await _client.rpc(
          'block_user',
          params: {'p_blocked_id': otherUserId},
        );
        return;
      } catch (rpcErr) {
        debugPrint(
          'ProfileService.blockUser rpc fallback → insert: $rpcErr',
        );
      }

      await _client.from('blocks').upsert({
        'blocker_id': uid,
        'blocked_id': otherUserId,
      });

      // Squad bağını kopar (RPC yoksa).
      try {
        await _client
            .from('squads')
            .delete()
            .or(
              'and(sender_id.eq.$uid,receiver_id.eq.$otherUserId),'
              'and(sender_id.eq.$otherUserId,receiver_id.eq.$uid)',
            );
      } catch (_) {}
    } catch (e, st) {
      debugPrint('ProfileService.blockUser: $e\n$st');
      rethrow;
    }
  }

  Future<void> unblockUser(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      try {
        await _client.rpc(
          'unblock_user',
          params: {'p_blocked_id': otherUserId},
        );
        return;
      } catch (rpcErr) {
        debugPrint(
          'ProfileService.unblockUser rpc fallback → delete: $rpcErr',
        );
      }

      await _client
          .from('blocks')
          .delete()
          .eq('blocker_id', uid)
          .eq('blocked_id', otherUserId);
    } catch (e, st) {
      debugPrint('ProfileService.unblockUser: $e\n$st');
      rethrow;
    }
  }

  /// Engellediğim kullanıcılar (profil + tarih).
  Future<List<UserProfile>> listBlockedUsers() async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      try {
        final rows = await _client.rpc('list_my_blocks');
        return (rows as List<dynamic>)
            .whereType<Map<Object?, Object?>>()
            .map((e) {
              final map = Map<String, dynamic>.from(e);
              return UserProfile(
                id: map['blocked_id'].toString(),
                username: (map['username'] as String?) ?? '@anon',
                bio: (map['bio'] as String?) ?? '',
                avatarUrl: map['avatar_url'] as String?,
                createdAt: map['created_at'] == null
                    ? null
                    : DateTime.tryParse(map['created_at'].toString())?.toUtc(),
              );
            })
            .toList(growable: false);
      } catch (rpcErr) {
        debugPrint(
          'ProfileService.listBlockedUsers rpc fallback → join: $rpcErr',
        );
      }

      final rows = await _client
          .from('blocks')
          .select('blocked_id, created_at, blocked:profiles!blocks_blocked_id_fkey(*)')
          .eq('blocker_id', uid)
          .order('created_at', ascending: false);

      final out = <UserProfile>[];
      for (final raw in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(raw as Map);
        final blocked = map['blocked'];
        if (blocked is Map) {
          out.add(UserProfile.fromRow(Map<String, dynamic>.from(blocked)));
        } else {
          final id = map['blocked_id']?.toString();
          if (id == null) continue;
          final p = await fetchProfile(userId: id);
          if (p != null) out.add(p);
        }
      }
      return out;
    } catch (e, st) {
      debugPrint('ProfileService.listBlockedUsers: $e\n$st');
      rethrow;
    }
  }

  /// Engellenen kullanıcı adları (yorum filtreleme — @ varyantları dahil).
  Future<Set<String>> blockedUsernameKeys() async {
    if (_uid == null || !SupabaseService.instance.isReady) {
      return const {};
    }
    try {
      final blocked = await listBlockedUsers();
      final keys = <String>{};
      for (final p in blocked) {
        final raw = p.username.trim().toLowerCase();
        if (raw.isEmpty) continue;
        keys.add(raw);
        keys.add(raw.startsWith('@') ? raw.substring(1) : '@$raw');
      }
      return keys;
    } catch (e, st) {
      debugPrint('ProfileService.blockedUsernameKeys: $e\n$st');
      return const {};
    }
  }

  static bool usernameMatchesBlocked(String username, Set<String> blockedKeys) {
    if (blockedKeys.isEmpty) return false;
    final raw = username.trim().toLowerCase();
    if (raw.isEmpty) return false;
    if (blockedKeys.contains(raw)) return true;
    final alt = raw.startsWith('@') ? raw.substring(1) : '@$raw';
    return blockedKeys.contains(alt);
  }

  Future<SquadEdge> sendSquadRequest(String receiverId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (receiverId == uid) {
      throw ArgumentError('Kendine squad isteği gönderemezsin.');
    }

    if (await areUsersBlocked(receiverId)) {
      throw StateError('Bu kullanıcıyla etkileşim engellendi.');
    }

    try {
      // RPC: rejected sonrası yeniden istek + tek yön unique.
      try {
        final row = await _client.rpc(
          'send_squad_request',
          params: {'p_receiver_id': receiverId},
        );
        return SquadEdge.fromRow(
          Map<String, dynamic>.from(row as Map),
          viewerId: uid,
        );
      } catch (rpcErr) {
        debugPrint(
          'ProfileService.sendSquadRequest rpc fallback → insert: $rpcErr',
        );
      }

      final row = await _client
          .from('squads')
          .insert({
            'sender_id': uid,
            'receiver_id': receiverId,
            'status': 'pending',
          })
          .select()
          .single();

      return SquadEdge.fromRow(Map<String, dynamic>.from(row), viewerId: uid);
    } catch (e, st) {
      debugPrint('ProfileService.sendSquadRequest: $e\n$st');
      rethrow;
    }
  }

  Future<SquadEdge> acceptSquadRequest(String requestId) async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      final row = await _client
          .from('squads')
          .update({'status': 'accepted'})
          .eq('id', requestId)
          .eq('receiver_id', uid)
          .select()
          .single();

      return SquadEdge.fromRow(Map<String, dynamic>.from(row), viewerId: uid);
    } catch (e, st) {
      debugPrint('ProfileService.acceptSquadRequest: $e\n$st');
      rethrow;
    }
  }

  Future<SquadEdge> rejectSquadRequest(String requestId) async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      try {
        final row = await _client.rpc(
          'reject_squad_request',
          params: {'p_request_id': requestId},
        );
        return SquadEdge.fromRow(
          Map<String, dynamic>.from(row as Map),
          viewerId: uid,
        );
      } catch (rpcErr) {
        debugPrint(
          'ProfileService.rejectSquadRequest rpc fallback → update: $rpcErr',
        );
      }

      final row = await _client
          .from('squads')
          .update({'status': 'rejected'})
          .eq('id', requestId)
          .eq('receiver_id', uid)
          .select()
          .single();

      return SquadEdge.fromRow(Map<String, dynamic>.from(row), viewerId: uid);
    } catch (e, st) {
      debugPrint('ProfileService.rejectSquadRequest: $e\n$st');
      rethrow;
    }
  }

  /// Gelen bekleyen squad istekleri.
  Future<List<SquadEdge>> getPendingSquadRequests() async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      final rows = await _client
          .from('squads')
          .select(
            'id, sender_id, receiver_id, status, created_at, '
            'sender:profiles!squads_sender_id_fkey(*)',
          )
          .eq('receiver_id', uid)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => SquadEdge.fromRow(
              Map<String, dynamic>.from(e),
              viewerId: uid,
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('ProfileService.getPendingSquadRequests: $e\n$st');
      try {
        final rows = await _client
            .from('squads')
            .select()
            .eq('receiver_id', uid)
            .eq('status', 'pending')
            .order('created_at', ascending: false);

        final edges = <SquadEdge>[];
        for (final raw in rows as List<dynamic>) {
          final map = Map<String, dynamic>.from(raw as Map);
          final senderId = map['sender_id']?.toString();
          UserProfile? other;
          if (senderId != null) {
            final p = await _client
                .from('profiles')
                .select()
                .eq('id', senderId)
                .maybeSingle();
            if (p != null) {
              other = UserProfile.fromRow(Map<String, dynamic>.from(p));
            }
          }
          edges.add(
            SquadEdge(
              id: map['id'].toString(),
              senderId: map['sender_id'].toString(),
              receiverId: map['receiver_id'].toString(),
              status: 'pending',
              createdAt: map['created_at'] == null
                  ? null
                  : DateTime.tryParse(map['created_at'].toString())?.toUtc(),
              otherProfile: other,
            ),
          );
        }
        return edges;
      } catch (e2, st2) {
        debugPrint(
          'ProfileService.getPendingSquadRequests fallback: $e2\n$st2',
        );
        rethrow;
      }
    }
  }

  Future<SquadConnectionStatus> getSquadStatus(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (otherUserId == uid) return SquadConnectionStatus.notConnected;

    try {
      final rows = await _client
          .from('squads')
          .select()
          .or(
            'and(sender_id.eq.$uid,receiver_id.eq.$otherUserId),'
            'and(sender_id.eq.$otherUserId,receiver_id.eq.$uid)',
          )
          .limit(1);

      if (rows.isEmpty) {
        return SquadConnectionStatus.notConnected;
      }

      final row = Map<String, dynamic>.from(rows.first as Map);
      final status = (row['status'] as String?) ?? 'pending';
      final senderId = row['sender_id']?.toString();

      if (status == 'accepted') return SquadConnectionStatus.accepted;
      if (status == 'rejected') return SquadConnectionStatus.rejected;
      if (status == 'pending') {
        if (senderId == uid) return SquadConnectionStatus.pendingSent;
        return SquadConnectionStatus.pendingReceived;
      }
      return SquadConnectionStatus.notConnected;
    } catch (e, st) {
      debugPrint('ProfileService.getSquadStatus: $e\n$st');
      rethrow;
    }
  }

  Future<List<SquadEdge>> getMySquadList() async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      final rows = await _client
          .from('squads')
          .select(
            'id, sender_id, receiver_id, status, created_at, '
            'sender:profiles!squads_sender_id_fkey(*), '
            'receiver:profiles!squads_receiver_id_fkey(*)',
          )
          .eq('status', 'accepted')
          .or('sender_id.eq.$uid,receiver_id.eq.$uid')
          .order('created_at', ascending: false);

      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => SquadEdge.fromRow(
              Map<String, dynamic>.from(e),
              viewerId: uid,
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('ProfileService.getMySquadList: $e\n$st');
      // FK isim varyasyonu — basit select'e düş.
      try {
        final rows = await _client
            .from('squads')
            .select()
            .eq('status', 'accepted')
            .or('sender_id.eq.$uid,receiver_id.eq.$uid');

        final edges = <SquadEdge>[];
        for (final raw in rows as List<dynamic>) {
          final map = Map<String, dynamic>.from(raw as Map);
          final otherId = map['sender_id']?.toString() == uid
              ? map['receiver_id']?.toString()
              : map['sender_id']?.toString();
          UserProfile? other;
          if (otherId != null) {
            final p = await _client
                .from('profiles')
                .select()
                .eq('id', otherId)
                .maybeSingle();
            if (p != null) {
              other = UserProfile.fromRow(Map<String, dynamic>.from(p));
            }
          }
          edges.add(
            SquadEdge(
              id: map['id'].toString(),
              senderId: map['sender_id'].toString(),
              receiverId: map['receiver_id'].toString(),
              status: (map['status'] as String?) ?? 'accepted',
              otherProfile: other,
            ),
          );
        }
        return edges;
      } catch (e2, st2) {
        debugPrint('ProfileService.getMySquadList fallback: $e2\n$st2');
        rethrow;
      }
    }
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    return path.substring(dot).toLowerCase();
  }

  static String _imageContentType(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}
