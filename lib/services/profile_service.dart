import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/squad_models.dart';
import '../models/user_profile.dart';
import '../models/vibe_post.dart';
import '../utils/storage_media_reference.dart';
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
      final row = await _client.rpc('get_my_profile');
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
            .select(
                'id, username, bio, avatar_url, created_at, email_domain, university_id')
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
              .select(
                  'id, username, bio, avatar_url, created_at, email_domain, university_id')
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

      List<dynamic> rows = const [];

      if (deviceId != null && deviceId.isNotEmpty) {
        rows = await _client
            .from('videos')
            .select(
              'id, video_url, username, caption, subtitle, track_label, '
              'vibe_count, comment_count, created_at, device_id',
            )
            .eq('device_id', deviceId)
            .order('created_at', ascending: false);
      }

      if (rows.isEmpty && usernames.isNotEmpty) {
        rows = await _client
            .from('videos')
            .select(
              'id, video_url, username, caption, subtitle, track_label, '
              'vibe_count, comment_count, created_at, device_id',
            )
            .inFilter('username', usernames.toList())
            .order('created_at', ascending: false);
      }

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
    final posts = rows.whereType<Map<Object?, Object?>>().map((e) {
      final map = Map<String, dynamic>.from(e);
      map.putIfAbsent('distance_m', () => null);
      map.putIfAbsent('score', () => null);
      final post = VibePost.fromRpc(map);
      return VibePost(
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
      );
    }).toList();
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

  /// Profil güncelle — opsiyonel avatar Storage'a yüklenir.
  Future<UserProfile> updateProfile({
    required String username,
    required String bio,
    String? avatarPath,
    bool clearAvatar = false,
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

    try {
      String? avatarUrl;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        avatarUrl = await _uploadAvatar(uid: uid, localPath: avatarPath);
      }

      final payload = <String, dynamic>{
        'username': trimmedUser,
        'bio': trimmedBio,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (clearAvatar && avatarUrl == null) 'avatar_url': null,
      };

      final row = await _client
          .from('profiles')
          .update(payload)
          .eq('id', uid)
          .select(
              'id, username, bio, avatar_url, created_at, email_domain, university_id')
          .single();

      // Yerel onboarding lakabını senkron tut.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username',
          trimmedUser.startsWith('@') ? trimmedUser : '@$trimmedUser');

      return UserProfile.fromRow(Map<String, dynamic>.from(row));
    } catch (e, st) {
      debugPrint('ProfileService.updateProfile: $e\n$st');
      rethrow;
    }
  }

  /// Öğrenci e-postasını bağla — domain = kampüs feed anahtarı.
  ///
  /// Migration `019_campus_email_domain.sql` → `claim_student_email`.
  /// Tam OTP doğrulama için Auth SMTP gerekir; bu çağrı profil üyeliğini yazar.
  Future<UserProfile> claimStudentEmail(String email) async {
    _assertSignedIn();
    try {
      final row = await SupabaseService.instance.claimStudentEmail(email);
      return UserProfile.fromRow(row);
    } catch (e, st) {
      debugPrint('ProfileService.claimStudentEmail: $e\n$st');
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

    // Merkezden kare kırp — daire avatar letterbox yapmaz.
    final squared = await _centerSquarePng(file);
    final uploadFile = squared ?? file;
    final ext = squared != null ? '.png' : _extensionOf(localPath);
    final objectPath = '$uid/${_uuid.v4()}$ext';

    await _client.storage.from(SupabaseConfig.avatarsBucket).upload(
          objectPath,
          uploadFile,
          fileOptions: FileOptions(
            contentType: _imageContentType(ext),
            upsert: true,
          ),
        );

    return _client.storage
        .from(SupabaseConfig.avatarsBucket)
        .getPublicUrl(objectPath);
  }

  /// Dikdörtgen görseli merkezden kare PNG’ye çevirir (max 1024px).
  static Future<File?> _centerSquarePng(File input) async {
    try {
      final bytes = await input.readAsBytes();
      if (bytes.isEmpty) return null;

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final side = math.min(src.width, src.height);
      if (side <= 0) return null;

      final outSide = math.min(side, 1024);
      final ox = (src.width - side) / 2.0;
      final oy = (src.height - side) / 2.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(
        src,
        Rect.fromLTWH(ox, oy, side.toDouble(), side.toDouble()),
        Rect.fromLTWH(0, 0, outSide.toDouble(), outSide.toDouble()),
        paint,
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(outSide, outSide);
      final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
      src.dispose();
      cropped.dispose();
      picture.dispose();
      if (png == null) return null;

      final out = File(
        '${input.parent.path}/nool_avatar_sq_${_uuid.v4()}.png',
      );
      await out.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return out;
    } catch (e, st) {
      debugPrint('ProfileService._centerSquarePng: $e\n$st');
      return null;
    }
  }

  /// Username → avatar_url eşlemesi (feed / yorum enrich).
  Future<Map<String, String?>> avatarUrlsForUsernames(
    Iterable<String> usernames,
  ) async {
    _assertReady();
    final variants = <String>{};
    for (final raw in usernames) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      variants.add(t);
      if (t.startsWith('@')) {
        variants.add(t.substring(1));
      } else {
        variants.add('@$t');
      }
    }
    if (variants.isEmpty) return const {};

    try {
      final rows = await _client
          .from('profiles')
          .select('username, avatar_url')
          .inFilter('username', variants.toList());

      final out = <String, String?>{};
      for (final row in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final name = (map['username'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final url = map['avatar_url'] as String?;
        out[name] = url;
        if (name.startsWith('@')) {
          out[name.substring(1)] = url;
        } else {
          out['@$name'] = url;
        }
      }
      return out;
    } catch (e, st) {
      debugPrint('ProfileService.avatarUrlsForUsernames: $e\n$st');
      return const {};
    }
  }

  /// GDPR / KVKK: Settings "hesabı sil" — tam medya + hesap wipe.
  Future<void> deleteAccount() => deleteUserAccountAndAssets();

  /// Delete all server-owned media first, then Auth and cascading account data.
  /// Keep the session on failure so the user can retry an incomplete deletion.
  Future<void> deleteUserAccountAndAssets() async {
    _assertSignedIn();
    await AuthService().authorizeAppleAccountDeletion();
    final rows = await _client.rpc('get_my_media_objects');
    final pathsByBucket = <String, List<String>>{};
    for (final raw in rows as List<dynamic>) {
      final row = Map<String, dynamic>.from(raw as Map);
      pathsByBucket
          .putIfAbsent(row['bucket_id'] as String, () => [])
          .add(row['name'] as String);
    }
    for (final entry in pathsByBucket.entries) {
      for (var i = 0; i < entry.value.length; i += 100) {
        final end = math.min(i + 100, entry.value.length);
        await _client.storage
            .from(entry.key)
            .remove(entry.value.sublist(i, end));
      }
    }
    await _client.rpc('delete_own_account');
    await OnboardingService.clearAccountLocalData();
    await AuthService().signOut();
  }

  /// Aktif kullanıcının yüklediği videolar (device_id ve/veya username).
  Future<List<VibePost>> getMyUploadedVideos() async {
    _assertReady();

    try {
      final uid = _uid;
      if (uid == null) return const [];
      final rows = await _client
          .from('videos')
          .select(
            'id, video_url, username, caption, subtitle, track_label, '
            'vibe_count, comment_count, created_at, user_id',
          )
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      final posts = rows.whereType<Map<Object?, Object?>>().map((e) {
        final map = Map<String, dynamic>.from(e);
        map.putIfAbsent('distance_m', () => null);
        map.putIfAbsent('score', () => null);
        final post = VibePost.fromRpc(map);
        return VibePost(
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
        );
      }).toList();

      return SupabaseService.instance.filterFreshVideos(posts);
    } catch (e, st) {
      debugPrint('ProfileService.getMyUploadedVideos: $e\n$st');
      rethrow;
    }
  }

  Future<SquadEdge> sendSquadRequest(String receiverId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (receiverId == uid) {
      throw ArgumentError('Kendine kanka isteği gönderemezsin.');
    }
    if (SupabaseService.instance.isProfileBlocked(userId: receiverId)) {
      throw StateError('Bu kullanıcı engelli.');
    }

    try {
      // Prefer block-aware RPC (016); fall back to direct insert.
      try {
        final row = await _client.rpc(
          'send_friend_request',
          params: {'p_receiver_id': receiverId},
        );
        return SquadEdge.fromRow(
          Map<String, dynamic>.from(row as Map),
          viewerId: uid,
        );
      } catch (e) {
        debugPrint('send_friend_request rpc: $e — falling back to insert');
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
      try {
        final row = await _client.rpc(
          'accept_friend_request',
          params: {'p_request_id': requestId},
        );
        return SquadEdge.fromRow(
          Map<String, dynamic>.from(row as Map),
          viewerId: uid,
        );
      } catch (e) {
        debugPrint('accept_friend_request rpc: $e — falling back');
      }

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
          'reject_friend_request',
          params: {'p_request_id': requestId},
        );
        return SquadEdge.fromRow(
          Map<String, dynamic>.from(row as Map),
          viewerId: uid,
        );
      } catch (e) {
        debugPrint('reject_friend_request rpc: $e — falling back');
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

  Future<void> cancelSquadRequest(String requestId) async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      try {
        await _client.rpc(
          'cancel_friend_request',
          params: {'p_request_id': requestId},
        );
        return;
      } catch (e) {
        debugPrint('cancel_friend_request rpc: $e — falling back');
      }

      await _client
          .from('squads')
          .delete()
          .eq('id', requestId)
          .eq('sender_id', uid)
          .eq('status', 'pending');
    } catch (e, st) {
      debugPrint('ProfileService.cancelSquadRequest: $e\n$st');
      rethrow;
    }
  }

  Future<void> removeFriend(String otherUserId) async {
    _assertSignedIn();
    final uid = _uid!;
    if (otherUserId == uid) return;

    try {
      try {
        await _client.rpc(
          'remove_friend',
          params: {'p_other_user_id': otherUserId},
        );
        return;
      } catch (e) {
        debugPrint('remove_friend rpc: $e — falling back');
      }

      await _client.from('squads').delete().eq('status', 'accepted').or(
            'and(sender_id.eq.$uid,receiver_id.eq.$otherUserId),'
            'and(sender_id.eq.$otherUserId,receiver_id.eq.$uid)',
          );
    } catch (e, st) {
      debugPrint('ProfileService.removeFriend: $e\n$st');
      rethrow;
    }
  }

  /// Incoming + outgoing pending friend requests.
  Future<({List<SquadEdge> incoming, List<SquadEdge> outgoing})>
      getPendingFriendRequests() async {
    _assertSignedIn();
    final uid = _uid!;

    try {
      final rows = await _client
          .from('squads')
          .select(
            'id, sender_id, receiver_id, status, created_at, '
            'sender:profiles!squads_sender_id_fkey(id,username,bio,avatar_url,created_at,email_domain,university_id), '
            'receiver:profiles!squads_receiver_id_fkey(id,username,bio,avatar_url,created_at,email_domain,university_id)',
          )
          .eq('status', 'pending')
          .or('sender_id.eq.$uid,receiver_id.eq.$uid')
          .order('created_at', ascending: false);

      final incoming = <SquadEdge>[];
      final outgoing = <SquadEdge>[];
      for (final raw in rows as List<dynamic>) {
        if (raw is! Map) continue;
        final edge = SquadEdge.fromRow(
          Map<String, dynamic>.from(raw),
          viewerId: uid,
        );
        final otherId = edge.senderId == uid ? edge.receiverId : edge.senderId;
        if (SupabaseService.instance.isProfileBlocked(userId: otherId)) {
          continue;
        }
        if (edge.receiverId == uid) {
          incoming.add(edge);
        } else {
          outgoing.add(edge);
        }
      }
      return (incoming: incoming, outgoing: outgoing);
    } catch (e, st) {
      debugPrint('ProfileService.getPendingFriendRequests: $e\n$st');
      // Fallback without embeds.
      final rows = await _client
          .from('squads')
          .select()
          .eq('status', 'pending')
          .or('sender_id.eq.$uid,receiver_id.eq.$uid')
          .order('created_at', ascending: false);

      final incoming = <SquadEdge>[];
      final outgoing = <SquadEdge>[];
      for (final raw in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(raw as Map);
        final edge = SquadEdge.fromRow(map, viewerId: uid);
        final otherId = edge.senderId == uid ? edge.receiverId : edge.senderId;
        if (SupabaseService.instance.isProfileBlocked(userId: otherId)) {
          continue;
        }
        UserProfile? other;
        try {
          final p = await _client
              .from('profiles')
              .select(
                  'id, username, bio, avatar_url, created_at, email_domain, university_id')
              .eq('id', otherId)
              .maybeSingle();
          if (p != null) {
            other = UserProfile.fromRow(Map<String, dynamic>.from(p));
          }
        } catch (_) {}
        final enriched = SquadEdge(
          id: edge.id,
          senderId: edge.senderId,
          receiverId: edge.receiverId,
          status: edge.status,
          createdAt: edge.createdAt,
          otherProfile: other,
        );
        if (edge.receiverId == uid) {
          incoming.add(enriched);
        } else {
          outgoing.add(enriched);
        }
      }
      return (incoming: incoming, outgoing: outgoing);
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
            'sender:profiles!squads_sender_id_fkey(id,username,bio,avatar_url,created_at,email_domain,university_id), '
            'receiver:profiles!squads_receiver_id_fkey(id,username,bio,avatar_url,created_at,email_domain,university_id)',
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
                .select(
                    'id, username, bio, avatar_url, created_at, email_domain, university_id')
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

  /// Kullanıcı adı ile insan ara.
  Future<List<UserProfile>> searchProfiles(String query,
      {int limit = 24}) async {
    _assertReady();
    final q = query.trim();
    if (q.isEmpty) return const [];

    final raw = q.startsWith('@') ? q.substring(1) : q;
    final pattern = '%$raw%';

    try {
      final byUser = await _client
          .from('profiles')
          .select(
              'id, username, bio, avatar_url, created_at, email_domain, university_id')
          .ilike('username', pattern)
          .limit(limit);

      final results = <String, UserProfile>{};
      for (final e in byUser) {
        final p = UserProfile.fromRow(Map<String, dynamic>.from(e as Map));
        results[p.id] = p;
      }

      if (results.length < limit) {
        final byBio = await _client
            .from('profiles')
            .select(
                'id, username, bio, avatar_url, created_at, email_domain, university_id')
            .ilike('bio', pattern)
            .limit(limit);
        for (final e in byBio) {
          final p = UserProfile.fromRow(Map<String, dynamic>.from(e as Map));
          results.putIfAbsent(p.id, () => p);
        }
      }

      return results.values.take(limit).toList();
    } catch (e, st) {
      debugPrint('ProfileService.searchProfiles: $e\n$st');
      rethrow;
    }
  }

  /// Server-authenticated ownership controls both row and media deletion.
  Future<void> deleteMyVideo(VibePost post) async {
    _assertSignedIn();
    final row = await _client
        .from('videos')
        .select('user_id, storage_path, video_url')
        .eq('id', post.id)
        .maybeSingle();
    if (row == null || row['user_id'] != _uid) {
      throw StateError('Bu videoyu yalnızca sahibi silebilir.');
    }
    final reference = StorageMediaReference.parse(
      row['video_url'] as String,
      projectUrl: SupabaseConfig.url,
    );
    if (reference == null) throw StateError('Video dosyası doğrulanamadı.');
    await _client.storage.from(reference.bucket).remove([reference.path]);
    await _client.rpc('delete_own_video', params: {
      'p_video_id': post.id,
      'p_device_id': _uid,
    });
  }

  Future<bool> isOwnVideo(VibePost post) async {
    if (_uid == null) return false;
    final row = await _client
        .from('videos')
        .select('id')
        .eq('id', post.id)
        .eq('user_id', _uid!)
        .maybeSingle();
    return row != null;
  }

  /// Caption güncelle.
  Future<void> updateMyVideoCaption({
    required String videoId,
    required String caption,
  }) async {
    _assertReady();
    try {
      await _client
          .from('videos')
          .update({'caption': caption.trim()}).eq('id', videoId);
    } catch (e, st) {
      debugPrint('ProfileService.updateMyVideoCaption: $e\n$st');
      rethrow;
    }
  }
}
