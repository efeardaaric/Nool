import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../l10n/app_strings.dart';
import '../models/campus_hotspot.dart';
import '../models/comment_item.dart';
import '../models/vibe_post.dart';
import '../utils/storage_media_reference.dart';

/// Supabase + PostGIS veri katmanı (singleton).
///
/// Feed sıralaması sunucuda:
/// `skor = vibe / (mesafe_m × yaş_saat)`
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  static const _uuid = Uuid();
  static const _prefsBlockedIdsKey = 'nool_blocked_user_ids';
  static const _prefsBlockedNamesKey = 'nool_blocked_usernames';

  bool _initialized = false;
  StreamSubscription<AuthState>? _authSub;

  double? _sessionLat;
  double? _sessionLng;

  /// Bellekte engellenen profil id / normalize username (feed safety net).
  final Set<String> _blockedUserIds = {};
  final Set<String> _blockedUsernames = {};

  bool get isReady => _initialized && SupabaseConfig.isConfigured;

  double? get sessionLatitude => _sessionLat;
  double? get sessionLongitude => _sessionLng;
  bool get hasSessionLocation => _sessionLat != null && _sessionLng != null;

  Set<String> get blockedUserIds => Set.unmodifiable(_blockedUserIds);
  Set<String> get blockedUsernames => Set.unmodifiable(_blockedUsernames);

  SupabaseClient get client {
    _assertReady();
    return Supabase.instance.client;
  }

  String? get _uid =>
      isReady ? Supabase.instance.client.auth.currentUser?.id : null;

  /// Resolve media at playback time so private buckets enforce current membership.
  Future<Uri> playableVideoUri(String url) async {
    final reference =
        StorageMediaReference.parse(url, projectUrl: SupabaseConfig.url);
    if (reference == null) return Uri.parse(url);
    _assertReady();
    final signed = await client.storage
        .from(reference.bucket)
        .createSignedUrl(reference.path, 300);
    return Uri.parse(signed);
  }

  /// Splash’tan gelen anlık GPS — feed/upload için oturum konumu.
  void setSessionLocation({
    required double latitude,
    required double longitude,
  }) {
    _sessionLat = latitude;
    _sessionLng = longitude;
  }

  /// SDK'yı bir kez başlatır. Anahtar yoksa no-op (demo feed devam eder).
  Future<void> initialize() async {
    if (_initialized) return;

    if (!SupabaseConfig.isConfigured) {
      debugPrint(
        'SupabaseService: SUPABASE_URL / SUPABASE_ANON_KEY tanımlı değil — '
        'uzak feed kapalı.',
      );
      return;
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    _initialized = true;

    await _loadLocalBlocks();
    await refreshBlockedUsers();

    await _authSub?.cancel();
    _authSub = client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed ||
          event == AuthChangeEvent.initialSession) {
        unawaited(refreshBlockedUsers());
      } else if (event == AuthChangeEvent.signedOut) {
        // Yerel yedek kalsın; bellek oturum dışı da filtreleyebilir.
        unawaited(_loadLocalBlocks());
      }
    });
  }

  /// PostGIS RPC: konuma göre skor sıralı yakındaki videolar.
  ///
  /// Skor = vibe / (mesafe × zaman). 24 saatten eski kayıtlar
  /// hem RPC'de hem istemcide elenir.
  /// [anchor*] verilirse o nokta etrafında (hotspot filtresi) sorgular.
  Future<List<VibePost>> fetchNearbyVideos({
    required double latitude,
    required double longitude,
    int limit = 40,
    double? anchorLatitude,
    double? anchorLongitude,
    double? radiusMeters,
  }) async {
    _assertReady();

    final params = <String, dynamic>{
      'p_lat': anchorLatitude ?? latitude,
      'p_lng': anchorLongitude ?? longitude,
      'p_limit': limit,
    };
    if (radiusMeters != null) {
      params['p_radius_m'] = radiusMeters;
    }

    final response = await client.rpc(
      SupabaseConfig.feedRpc,
      params: params,
    );

    final rows = (response as List<dynamic>)
        .whereType<Map<Object?, Object?>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final posts = rows.map(VibePost.fromRpc).toList();
    return _attachAvatarUrls(filterBlockedPosts(filterFreshVideos(posts)));
  }

  /// Yoğunluk halkaları: 500m → 1 → 2 → 3 → 5 → 10 → 20 km.
  /// Boş halkada bir üst halkaya çıkar; 20 km’de de yoksa boş döner
  /// (worldwide / popüler fallback yok — yalnızca kendi çevresi).
  ///
  /// [onProgress] her aşamada UI’ya bildirir.
  /// [isCancelled] true dönerse sonraki sorgular atlanır (race güvenliği).
  Future<NearbyFeedResult> fetchNearbyVideosExpanding({
    required double latitude,
    required double longitude,
    int limit = 40,
    double? anchorLatitude,
    double? anchorLongitude,
    List<double> radiiMeters = SupabaseConfig.feedSearchRadiiMeters,
    void Function(NearbyScanProgress progress)? onProgress,
    bool Function()? isCancelled,
    Duration stageHold = const Duration(milliseconds: 2200),
  }) async {
    _assertReady();

    bool cancelled() => isCancelled?.call() ?? false;

    for (final radius in radiiMeters) {
      if (cancelled()) {
        return NearbyFeedResult.empty(cancelled: true);
      }

      onProgress?.call(
        NearbyScanProgress.radius(radiusMeters: radius),
      );
      if (stageHold > Duration.zero) {
        await Future<void>.delayed(stageHold);
      }
      if (cancelled()) {
        return NearbyFeedResult.empty(cancelled: true);
      }

      final posts = await fetchNearbyVideos(
        latitude: latitude,
        longitude: longitude,
        limit: limit,
        anchorLatitude: anchorLatitude,
        anchorLongitude: anchorLongitude,
        radiusMeters: radius,
      );
      if (cancelled()) {
        return NearbyFeedResult.empty(cancelled: true);
      }
      if (posts.isNotEmpty) {
        return NearbyFeedResult(
          posts: posts,
          matchedRadiusMeters: radius,
          usedFallback: false,
        );
      }
    }

    // Vicinity tükendi — uzak / global içerik yok.
    return NearbyFeedResult.empty(cancelled: cancelled());
  }

  /// Konum filtresi yok — son 24 saatte en çok vibe alan videolar.
  Future<List<VibePost>> fetchPopularVideos({
    int limit = SupabaseConfig.feedFallbackLimit,
  }) async {
    return _fetchTableVideos(
      limit: limit,
      orderBy: 'vibe_count',
      distanceLabel: 'şehir',
      subtitleFallback: 'Popüler',
    );
  }

  /// Konum + vibe sırası yok — son 24 saatteki tüm taze videolar (yeniden eskiye).
  Future<List<VibePost>> fetchAllFreshVideos({
    int limit = SupabaseConfig.feedFallbackLimit,
  }) async {
    return _fetchTableVideos(
      limit: limit,
      orderBy: 'created_at',
      distanceLabel: 'global vibe',
      subtitleFallback: 'Tüm kampüs',
    );
  }

  /// Vibing sekmesi: konum yok; son 24s,
  /// `score = vibe_count / max(hours_since_created, 0.01)` azalan.
  Future<List<VibePost>> fetchVibingVideos({
    int limit = SupabaseConfig.feedFallbackLimit,
  }) async {
    final posts = await fetchAllFreshVideos(limit: limit);
    final now = DateTime.now().toUtc();

    double vibingScore(VibePost post) {
      final created = post.createdAt ?? now;
      final hours =
          now.difference(created).inMilliseconds / (1000.0 * 60.0 * 60.0);
      final denom = hours < 0.01 ? 0.01 : hours;
      return post.vibeCount / denom;
    }

    final ranked = List<VibePost>.from(posts)
      ..sort((a, b) => vibingScore(b).compareTo(vibingScore(a)));

    return ranked
        .map(
          (post) => post.copyWith(
            distanceLabel: 'vibing',
            subtitle: post.subtitle.isEmpty ? 'Vibing' : post.subtitle,
            score: vibingScore(post),
          ),
        )
        .toList(growable: false);
  }

  /// Kampüs üyelik + feed sonucu.
  ///
  /// Migration: `019_campus_email_domain.sql` (+ `012_profiles_university_id`).
  Future<CampusFeedResult> fetchCampusFeed({
    int limit = SupabaseConfig.feedFallbackLimit,
  }) async {
    _assertReady();

    final uid = _uid;
    if (uid == null) {
      return const CampusFeedResult(
        posts: [],
        hasCampusAccess: false,
      );
    }

    String? emailDomain;
    try {
      final row = await client
          .from('profiles')
          .select('email_domain, university_id')
          .eq('id', uid)
          .maybeSingle();
      if (row != null) {
        emailDomain = _trimDomain(
          (row['email_domain'] as String?) ?? (row['university_id'] as String?),
        );
      }
    } catch (e) {
      debugPrint(
        'SupabaseService.fetchCampusFeed: profile domain okunamadı '
        '(migration 019?). $e',
      );
    }

    if (emailDomain == null) {
      return const CampusFeedResult(
        posts: [],
        hasCampusAccess: false,
      );
    }

    try {
      final response = await client.rpc(
        'get_campus_videos',
        params: {'p_limit': limit},
      );
      final rows = (response as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final posts = rows.map((row) {
        final mapped = Map<String, dynamic>.from(row);
        mapped.putIfAbsent('distance_m', () => null);
        final post = VibePost.fromRpc(mapped);
        return post.copyWith(
          distanceLabel: 'kampüs',
          subtitle: post.subtitle.isEmpty ? 'Kampüs' : post.subtitle,
        );
      }).toList();

      final filtered = filterBlockedPosts(posts);
      final withAvatars = await _attachAvatarUrls(filtered);
      return CampusFeedResult(
        posts: withAvatars,
        hasCampusAccess: true,
        emailDomain: emailDomain,
      );
    } catch (e) {
      // RPC yoksa (migration öncesi) eski heuristic’e düşme — boş + erişim var.
      debugPrint(
        'SupabaseService.fetchCampusFeed: get_campus_videos failed. $e',
      );
      return CampusFeedResult(
        posts: const [],
        hasCampusAccess: true,
        emailDomain: emailDomain,
      );
    }
  }

  /// Geriye uyum — yalnızca post listesi.
  Future<List<VibePost>> fetchCampusVideos({
    int limit = SupabaseConfig.feedFallbackLimit,
  }) async {
    final result = await fetchCampusFeed(limit: limit);
    return result.posts;
  }

  static String? _trimDomain(String? raw) {
    final d = raw?.trim().toLowerCase();
    if (d == null || d.isEmpty) return null;
    return d;
  }

  /// Öğrenci e-postasını bağla → `claim_student_email` RPC.
  Future<Map<String, dynamic>> claimStudentEmail(String email) async {
    _assertReady();
    if (_uid == null) {
      throw StateError('Kampüs e-postası için giriş yapmalısın.');
    }
    final inserted = await client.rpc(
      'claim_student_email',
      params: {'p_email': email.trim()},
    );
    if (inserted is Map<String, dynamic>) return inserted;
    if (inserted is List && inserted.isNotEmpty) {
      return Map<String, dynamic>.from(inserted.first as Map);
    }
    return Map<String, dynamic>.from(inserted as Map);
  }

  Future<List<VibePost>> _fetchTableVideos({
    required int limit,
    required String orderBy,
    required String distanceLabel,
    required String subtitleFallback,
  }) async {
    _assertReady();

    final since = DateTime.now()
        .toUtc()
        .subtract(SupabaseConfig.videoTtl)
        .toIso8601String();

    List<dynamic> response;
    try {
      response = await client
          .from('videos')
          .select(
            'id, video_url, username, caption, subtitle, track_label, '
            'vibe_count, comment_count, created_at, reaction_counts',
          )
          .gte('created_at', since)
          .order(orderBy, ascending: false)
          .limit(limit);
    } catch (e) {
      // reaction_counts kolonu yoksa (migration 013 öncesi) düş.
      debugPrint(
        'SupabaseService._fetchTableVideos: reaction_counts select failed, '
        'retrying without. $e',
      );
      response = await client
          .from('videos')
          .select(
            'id, video_url, username, caption, subtitle, track_label, '
            'vibe_count, comment_count, created_at',
          )
          .gte('created_at', since)
          .order(orderBy, ascending: false)
          .limit(limit);
    }

    final rows = response
        .whereType<Map<Object?, Object?>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final posts = rows.map((row) {
      final mapped = Map<String, dynamic>.from(row);
      mapped.putIfAbsent('distance_m', () => null);
      mapped.putIfAbsent('score', () => null);
      final post = VibePost.fromRpc(mapped);
      return post.copyWith(
        distanceLabel: distanceLabel,
        subtitle: post.subtitle.isEmpty ? subtitleFallback : post.subtitle,
      );
    }).toList();

    // created_at select’ten geliyor; yine de TTL doğrula.
    // created_at parse edilemezse (null) videoyu düşürme — global fallback’te göster.
    final fresh = filterBlockedPosts(filterFreshVideos(posts));
    if (fresh.isNotEmpty) return _attachAvatarUrls(fresh);
    return _attachAvatarUrls(filterBlockedPosts(posts));
  }

  /// `profiles.avatar_url` ile feed postlarını zenginleştir.
  Future<List<VibePost>> _attachAvatarUrls(List<VibePost> posts) async {
    if (posts.isEmpty) return posts;

    final variants = <String>{};
    for (final post in posts) {
      final t = post.username.trim();
      if (t.isEmpty) continue;
      variants.add(t);
      if (t.startsWith('@')) {
        variants.add(t.substring(1));
      } else {
        variants.add('@$t');
      }
    }
    if (variants.isEmpty) return posts;

    try {
      final rows = await client
          .from('profiles')
          .select('username, avatar_url')
          .inFilter('username', variants.toList());

      final map = <String, String?>{};
      for (final row in rows as List<dynamic>) {
        final m = Map<String, dynamic>.from(row as Map);
        final name = (m['username'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final url = m['avatar_url'] as String?;
        map[name] = url;
        if (name.startsWith('@')) {
          map[name.substring(1)] = url;
        } else {
          map['@$name'] = url;
        }
      }

      return posts
          .map((p) => p.copyWith(avatarUrl: map[p.username] ?? p.avatarUrl))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('SupabaseService._attachAvatarUrls: $e\n$st');
      return posts;
    }
  }

  /// Aktif video kümeleri (trend / ısı) — [radiusMeters] yoğunluk halkası.
  Future<List<CampusHotspot>> fetchTrendingHotspots({
    required double latitude,
    required double longitude,
    double radiusMeters = SupabaseConfig.hotspotRadiusMeters,
    int limit = 40,
  }) async {
    _assertReady();

    final response = await client.rpc(
      SupabaseConfig.hotspotsRpc,
      params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_radius_m': radiusMeters,
        'p_limit': limit,
      },
    );

    final rows = (response as List<dynamic>)
        .whereType<Map<Object?, Object?>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return rows
        .map(
          (row) => CampusHotspot.fromRpc(
            row,
            vicinityRadiusMeters: radiusMeters,
          ),
        )
        .toList(growable: false);
  }

  /// Yoğunluğa göre halka seç: seyrekse genişlet, yoğunksa dar kal.
  /// Manuel [forcedRadiusMeters] verilirse yalnızca o halka sorgulanır.
  Future<DensityHotspotsResult> fetchTrendingHotspotsByDensity({
    required double latitude,
    required double longitude,
    double? forcedRadiusMeters,
    int limit = 40,
    int minVideos = SupabaseConfig.densityMinVideos,
    List<double> radiiMeters = SupabaseConfig.densityRadiiMeters,
    bool Function()? isCancelled,
  }) async {
    _assertReady();

    bool cancelled() => isCancelled?.call() ?? false;

    if (forcedRadiusMeters != null) {
      final spots = await fetchTrendingHotspots(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: forcedRadiusMeters,
        limit: limit,
      );
      return DensityHotspotsResult(
        hotspots: spots,
        radiusMeters: forcedRadiusMeters,
        totalVideos: spots.fold<int>(0, (n, s) => n + s.dropCount),
        autoExpanded: false,
      );
    }

    List<CampusHotspot> lastSpots = const [];
    var lastRadius = radiiMeters.first;
    var lastTotal = 0;

    for (final radius in radiiMeters) {
      if (cancelled()) {
        return DensityHotspotsResult(
          hotspots: lastSpots,
          radiusMeters: lastRadius,
          totalVideos: lastTotal,
          autoExpanded: lastRadius != radiiMeters.first,
          cancelled: true,
        );
      }

      final spots = await fetchTrendingHotspots(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radius,
        limit: limit,
      );
      final total = spots.fold<int>(0, (n, s) => n + s.dropCount);
      lastSpots = spots;
      lastRadius = radius;
      lastTotal = total;

      // Yeterli yoğunluk → bu halkada kal.
      if (total >= minVideos) {
        return DensityHotspotsResult(
          hotspots: spots,
          radiusMeters: radius,
          totalVideos: total,
          autoExpanded: radius != radiiMeters.first,
        );
      }
    }

    return DensityHotspotsResult(
      hotspots: lastSpots,
      radiusMeters: lastRadius,
      totalVideos: lastTotal,
      autoExpanded: lastRadius != radiiMeters.first,
    );
  }

  /// İstemci tarafı TTL doğrulaması — 24 saatten eski videolar feed'e girmez.
  List<VibePost> filterFreshVideos(List<VibePost> posts, {DateTime? now}) {
    final anchor = (now ?? DateTime.now()).toUtc();
    return posts.where((post) {
      final created = post.createdAt;
      if (created == null) return false;
      return isWithinTtl(created, now: anchor);
    }).toList();
  }

  /// Engellenen kullanıcıların drop’larını istemci tarafında da eler (safety net).
  List<VibePost> filterBlockedPosts(List<VibePost> posts) {
    if (_blockedUsernames.isEmpty) return posts;
    return posts
        .where((post) => !isUsernameBlocked(post.username))
        .toList(growable: false);
  }

  /// Normalize: trim + leading `@` kaldır + lower.
  static String? normalizeUsername(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.startsWith('@')) s = s.substring(1);
    s = s.trim().toLowerCase();
    return s.isEmpty ? null : s;
  }

  bool isUsernameBlocked(String? username) {
    final norm = normalizeUsername(username);
    if (norm == null) return false;
    return _blockedUsernames.contains(norm);
  }

  bool isUserIdBlocked(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return _blockedUserIds.contains(userId);
  }

  bool isProfileBlocked({String? userId, String? username}) {
    if (isUserIdBlocked(userId)) return true;
    return isUsernameBlocked(username);
  }

  /// Sunucu + SharedPreferences yedekten engel listesini yeniler.
  Future<void> refreshBlockedUsers() async {
    await _loadLocalBlocks();
    if (!isReady || _uid == null) return;

    try {
      final rows = await client
          .from('blocked_users')
          .select('blocked_user_id')
          .eq('blocker_id', _uid!);

      final ids = <String>{};
      for (final raw in (rows as List<dynamic>)) {
        if (raw is! Map) continue;
        final id =
            Map<String, dynamic>.from(raw)['blocked_user_id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }

      final names = <String>{};
      if (ids.isNotEmpty) {
        final profiles = await client
            .from('profiles')
            .select('id, username')
            .inFilter('id', ids.toList());
        for (final raw in (profiles as List<dynamic>)) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final norm = normalizeUsername(row['username']?.toString());
          if (norm != null) names.add(norm);
        }
      }

      // Yerel yedekteki username’leri de koru (anon engeller).
      final localNames = Set<String>.from(_blockedUsernames);

      _blockedUserIds
        ..clear()
        ..addAll(ids);
      _blockedUsernames
        ..clear()
        ..addAll(names)
        ..addAll(localNames);
      await _persistLocalBlocks();
    } catch (e, st) {
      debugPrint('SupabaseService.refreshBlockedUsers: $e\n$st');
    }
  }

  /// Video şikayeti — oturum zorunlu.
  ///
  /// Aynı kullanıcı aynı videoyu yeniden şikayet ederse (unique) sessizce OK;
  /// 3 farklı kullanıcı sonrası sunucu videoyu `suspended` yapar.
  Future<void> reportVideo({
    required String videoId,
    required String reason,
  }) async {
    _assertReady();
    final uid = _uid;
    if (uid == null) {
      throw StateError('Şikayet için giriş yapmalısın.');
    }
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Şikayet nedeni boş olamaz.');
    }

    try {
      await client.from('reports').insert({
        'reporter_id': uid,
        'reported_video_id': videoId,
        'reason': trimmed,
      });
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!(msg.contains('duplicate') || msg.contains('unique'))) {
        rethrow;
      }
      // Zaten şikayet etmiş — yerel gizleme yine başarılı sayılır.
    }
  }

  /// Kullanıcıyı kalıcı engelle (profiles.id).
  Future<void> blockUser({required String blockedUserId}) async {
    _assertReady();
    final uid = _uid;
    if (uid == null) {
      throw StateError('Engellemek için giriş yapmalısın.');
    }
    if (blockedUserId.isEmpty) {
      throw ArgumentError('blockedUserId boş olamaz.');
    }
    if (blockedUserId == uid) {
      throw StateError('Kendini engelleyemezsin.');
    }

    try {
      await client.from('blocked_users').insert({
        'blocker_id': uid,
        'blocked_user_id': blockedUserId,
      });
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!(msg.contains('duplicate') || msg.contains('unique'))) {
        rethrow;
      }
    }

    _blockedUserIds.add(blockedUserId);

    try {
      final row = await client
          .from('profiles')
          .select('username')
          .eq('id', blockedUserId)
          .maybeSingle();
      final norm = normalizeUsername(row?['username']?.toString());
      if (norm != null) _blockedUsernames.add(norm);
    } catch (e) {
      debugPrint('SupabaseService.blockUser username lookup: $e');
    }

    await _persistLocalBlocks();
  }

  /// Feed yalnızca username biliyorsa — profil id çözüp engeller.
  Future<void> blockUserByUsername(String username) async {
    _assertReady();
    if (_uid == null) {
      throw StateError('Engellemek için giriş yapmalısın.');
    }

    final raw = username.trim();
    if (raw.isEmpty) {
      throw ArgumentError('username boş olamaz.');
    }

    final candidates = <String>{
      raw,
      raw.startsWith('@') ? raw.substring(1) : '@$raw',
    };

    Map<String, dynamic>? profile;
    for (final name in candidates) {
      final row = await client
          .from('profiles')
          .select('id, username')
          .eq('username', name)
          .maybeSingle();
      if (row != null) {
        profile = Map<String, dynamic>.from(row);
        break;
      }
    }

    if (profile == null) {
      // Profil yoksa yine de yerel filtre uygula (anon drop’lar).
      final norm = normalizeUsername(raw);
      if (norm != null) {
        _blockedUsernames.add(norm);
        await _persistLocalBlocks();
      }
      return;
    }

    final id = profile['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Profil id çözülemedi.');
    }

    final norm = normalizeUsername(profile['username']?.toString() ?? raw);
    if (norm != null) _blockedUsernames.add(norm);

    await blockUser(blockedUserId: id);
  }

  Future<void> _loadLocalBlocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_prefsBlockedIdsKey) ?? const [];
      final names = prefs.getStringList(_prefsBlockedNamesKey) ?? const [];
      _blockedUserIds
        ..clear()
        ..addAll(ids);
      _blockedUsernames
        ..clear()
        ..addAll(
          names.map(normalizeUsername).whereType<String>(),
        );
    } catch (e) {
      debugPrint('SupabaseService._loadLocalBlocks: $e');
    }
  }

  Future<void> _persistLocalBlocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsBlockedIdsKey,
        _blockedUserIds.toList(growable: false),
      );
      await prefs.setStringList(
        _prefsBlockedNamesKey,
        _blockedUsernames.toList(growable: false),
      );
    } catch (e) {
      debugPrint('SupabaseService._persistLocalBlocks: $e');
    }
  }

  /// Video 24 saatlik pencerede mi?
  bool isWithinTtl(DateTime createdAt, {DateTime? now}) {
    final anchor = (now ?? DateTime.now()).toUtc();
    final age = anchor.difference(createdAt.toUtc());
    return !age.isNegative && age <= SupabaseConfig.videoTtl;
  }

  /// Yerel skor: vibe / (mesafe × zaman_saat). Sıfır bölmeyi engeller.
  static double computeScore({
    required int vibeCount,
    required double distanceMeters,
    required Duration age,
  }) {
    final distance = distanceMeters < 1 ? 1.0 : distanceMeters;
    final hours = age.inMilliseconds / Duration.millisecondsPerHour;
    final timeFactor = hours < 0.01 ? 0.01 : hours;
    return vibeCount / (distance * timeFactor);
  }

  /// Videoyu Storage'a yükler, `videos` tablosuna Point(lng, lat) kaydeder.
  ///
  /// [visibility]: `public` (Near You) veya `campus` (yalnız aynı domain).
  Future<VibePost> uploadVideo({
    required File file,
    required double latitude,
    required double longitude,
    required String username,
    required String deviceId,
    String caption = '',
    String subtitle = '',
    String trackLabel = 'original audio',
    String visibility = 'public',
  }) async {
    _assertReady();

    final uid = _uid;
    if (uid == null) {
      throw StateError('Video paylaşmak için giriş yapmalısın.');
    }
    if (!await file.exists()) {
      throw StateError('Video dosyası bulunamadı: ${file.path}');
    }

    final vis = visibility.trim().toLowerCase();
    if (vis != 'public' && vis != 'campus') {
      throw ArgumentError('visibility public veya campus olmalı.');
    }

    final id = _uuid.v4();
    final ext = _extensionOf(file.path);
    final objectPath = '$uid/$id$ext';

    await client.storage.from(SupabaseConfig.videosBucket).upload(
          objectPath,
          file,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(ext),
            upsert: false,
          ),
        );

    final videoUrl = client.storage
        .from(SupabaseConfig.videosBucket)
        .getPublicUrl(objectPath);

    // Point(lng, lat) PostGIS tarafında ST_MakePoint ile yazılır.
    dynamic inserted;
    try {
      inserted = await client.rpc(
        'create_video',
        params: {
          'p_id': id,
          'p_device_id': deviceId,
          'p_username': username,
          'p_caption': caption,
          'p_subtitle': subtitle,
          'p_track_label': trackLabel,
          'p_storage_path': objectPath,
          'p_video_url': videoUrl,
          'p_lat': latitude,
          'p_lng': longitude,
          'p_visibility': vis,
        },
      );
    } catch (_) {
      // Metadata failed: remove the upload rather than leave a public orphan.
      try {
        await client.storage
            .from(SupabaseConfig.videosBucket)
            .remove([objectPath]);
      } catch (e) {
        debugPrint('Video upload cleanup failed: $e');
      }
      rethrow;
    }

    final row = inserted is Map<String, dynamic>
        ? inserted
        : Map<String, dynamic>.from(
            (inserted as List<dynamic>).first as Map,
          );

    final createdAt = DateTime.tryParse('${row['created_at']}')?.toUtc() ??
        DateTime.now().toUtc();

    return VibePost(
      id: id,
      videoUrl: videoUrl,
      username: username,
      caption: caption,
      distanceLabel: '0m yakınında',
      subtitle: subtitle.isEmpty ? 'Az önce' : subtitle,
      trackLabel: trackLabel,
      vibeCountLabel: '0 Vibe',
      commentCountLabel: '0',
      vibeCount: 0,
      commentCount: 0,
      distanceMeters: 0,
      score: 0,
      createdAt: createdAt,
    );
  }

  /// Vibe sayacını +1 (legacy RPC — idempotent; prefers [toggleVibe]).
  Future<void> incrementVibe(String videoId) async {
    _assertReady();
    await client.rpc('increment_vibe', params: {'p_video_id': videoId});
  }

  /// Which of [videoIds] the signed-in user has already vibed.
  Future<Set<String>> fetchMyVibedVideoIds(Iterable<String> videoIds) async {
    _assertReady();
    final uid = _uid;
    if (uid == null) return {};

    final ids = videoIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return {};

    try {
      final rows = await client
          .from('video_vibes')
          .select('video_id')
          .eq('user_id', uid)
          .inFilter('video_id', ids);
      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => (e['video_id'] as String?)?.trim())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('SupabaseService.fetchMyVibedVideoIds: $e');
      return {};
    }
  }

  /// Toggle vibe for the signed-in user.
  ///
  /// Already vibed → DELETE (un-vibe). Otherwise → INSERT.
  /// Returns server membership + refreshed [vibe_count].
  Future<({bool isVibed, int vibeCount})> toggleVibe(String videoId) async {
    _assertReady();
    final uid = _uid;
    if (uid == null) {
      throw StateError('Vibe requires a signed-in user.');
    }

    final existing = await client
        .from('video_vibes')
        .select('id')
        .eq('video_id', videoId)
        .eq('user_id', uid)
        .maybeSingle();

    final bool isVibed;
    if (existing != null) {
      await client
          .from('video_vibes')
          .delete()
          .eq('id', existing['id'] as String);
      isVibed = false;
    } else {
      await client.from('video_vibes').insert({
        'video_id': videoId,
        'user_id': uid,
      });
      isVibed = true;
    }

    var vibeCount = 0;
    try {
      final row = await client
          .from('videos')
          .select('vibe_count')
          .eq('id', videoId)
          .maybeSingle();
      vibeCount = (row?['vibe_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('SupabaseService.toggleVibe count refresh: $e');
    }
    return (isVibed: isVibed, vibeCount: vibeCount);
  }

  static const reactionTypes = <String>[
    'laugh',
    'pepper',
    'smile',
    'angry',
    'star',
  ];

  /// Current user's reaction types on a video (may be empty / multi).
  Future<Set<String>> fetchMyReactions(String videoId) async {
    _assertReady();
    final uid = _uid;
    if (uid == null) return {};

    try {
      final rows = await client
          .from('video_reactions')
          .select('reaction_type')
          .eq('video_id', videoId)
          .eq('user_id', uid);
      return (rows as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => (e['reaction_type'] as String?)?.trim())
          .whereType<String>()
          .where((t) => t.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('SupabaseService.fetchMyReactions: $e');
      return {};
    }
  }

  /// Toggle one emoji reaction for the signed-in user.
  ///
  /// Same type already present → DELETE (unvote).
  /// Otherwise → INSERT (vote).
  /// Returns refreshed `videos.reaction_counts` after the trigger runs.
  Future<Map<String, int>> toggleReaction({
    required String videoId,
    required String reactionType,
  }) async {
    _assertReady();
    final uid = _uid;
    if (uid == null) {
      throw StateError('Reaction requires a signed-in user.');
    }
    if (!reactionTypes.contains(reactionType)) {
      throw ArgumentError.value(reactionType, 'reactionType');
    }

    final existing = await client
        .from('video_reactions')
        .select('id')
        .eq('video_id', videoId)
        .eq('user_id', uid)
        .eq('reaction_type', reactionType)
        .maybeSingle();

    if (existing != null) {
      await client
          .from('video_reactions')
          .delete()
          .eq('id', existing['id'] as String);
    } else {
      await client.from('video_reactions').insert({
        'video_id': videoId,
        'user_id': uid,
        'reaction_type': reactionType,
      });
    }

    try {
      final row = await client
          .from('videos')
          .select('reaction_counts')
          .eq('id', videoId)
          .maybeSingle();
      return VibePost.parseReactionCounts(row?['reaction_counts']);
    } catch (e) {
      debugPrint('SupabaseService.toggleReaction counts refresh: $e');
      return const {};
    }
  }

  /// Video yorumları — Realtime stream (yeniden eskiden yeniye).
  Stream<List<CommentItem>> watchComments(String videoId) {
    _assertReady();
    return client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('video_id', videoId)
        .order('created_at', ascending: true)
        .map(
          (rows) => rows
              .map((row) => CommentItem.fromRow(Map<String, dynamic>.from(row)))
              .toList(growable: false),
        );
  }

  /// Yorum ekle (filtre istemci tarafında uygulanmış olmalı).
  Future<CommentItem> postComment({
    required String videoId,
    required String deviceId,
    required String username,
    required String body,
  }) async {
    _assertReady();
    if (_uid == null) {
      throw StateError('Yorum yapmak için giriş yapmalısın.');
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Boş yorum gönderilemez.');
    }
    if (trimmed.length > 500) {
      throw ArgumentError('Yorum en fazla 500 karakter olabilir.');
    }

    final row = await client
        .from('comments')
        .insert({
          'video_id': videoId,
          'user_id': _uid,
          'device_id': deviceId,
          'username': username,
          'body': trimmed,
        })
        .select()
        .single();

    return CommentItem.fromRow(Map<String, dynamic>.from(row));
  }

  void _assertReady() {
    if (!_initialized || !SupabaseConfig.isConfigured) {
      throw StateError(
        'Supabase hazır değil. SUPABASE_URL ve SUPABASE_ANON_KEY verin, '
        'ardından SupabaseService.instance.initialize() çağırın.',
      );
    }
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

/// Radar / UI için tarama aşaması.
class NearbyScanProgress {
  const NearbyScanProgress._({
    required this.isFallback,
    this.radiusMeters,
  });

  factory NearbyScanProgress.radius({required double radiusMeters}) {
    return NearbyScanProgress._(
      isFallback: false,
      radiusMeters: radiusMeters,
    );
  }

  factory NearbyScanProgress.fallback() {
    return const NearbyScanProgress._(isFallback: true);
  }

  final bool isFallback;
  final double? radiusMeters;

  String get statusMessage {
    final s = AppStrings.fromSettings();
    if (isFallback) return s.radarFallback;
    final meters = radiusMeters?.round();
    if (meters == null) return s.radarScanning;
    return s.radarAtMeters(meters);
  }
}

/// Trend yoğunluk halkası sonucu.
class DensityHotspotsResult {
  const DensityHotspotsResult({
    required this.hotspots,
    required this.radiusMeters,
    required this.totalVideos,
    required this.autoExpanded,
    this.cancelled = false,
  });

  final List<CampusHotspot> hotspots;
  final double radiusMeters;
  final int totalVideos;
  final bool autoExpanded;
  final bool cancelled;
}

/// Dinamik yarıçap araması sonucu.
class NearbyFeedResult {
  const NearbyFeedResult({
    required this.posts,
    required this.matchedRadiusMeters,
    required this.usedFallback,
    this.cancelled = false,
  });

  factory NearbyFeedResult.empty({bool cancelled = false}) {
    return NearbyFeedResult(
      posts: const [],
      matchedRadiusMeters: null,
      usedFallback: false,
      cancelled: cancelled,
    );
  }

  final List<VibePost> posts;
  final double? matchedRadiusMeters;
  final bool usedFallback;
  final bool cancelled;
}

/// Campus sekmesi sonucu — erişim + domain + postlar.
class CampusFeedResult {
  const CampusFeedResult({
    required this.posts,
    required this.hasCampusAccess,
    this.emailDomain,
  });

  final List<VibePost> posts;

  /// `profiles.email_domain` / `university_id` dolu mu.
  final bool hasCampusAccess;

  /// Bağlı kampüs domain’i (örn. stu.istinye.edu.tr).
  final String? emailDomain;
}
