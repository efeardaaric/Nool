import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/campus_hotspot.dart';
import '../models/comment_item.dart';
import '../models/vibe_post.dart';

/// Supabase + PostGIS veri katmanı (singleton).
///
/// Feed sıralaması sunucuda:
/// `skor = vibe / (mesafe_m × yaş_saat)`
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  static const _uuid = Uuid();

  bool _initialized = false;

  double? _sessionLat;
  double? _sessionLng;

  bool get isReady => _initialized && SupabaseConfig.isConfigured;

  double? get sessionLatitude => _sessionLat;
  double? get sessionLongitude => _sessionLng;
  bool get hasSessionLocation =>
      _sessionLat != null && _sessionLng != null;

  SupabaseClient get client {
    _assertReady();
    return Supabase.instance.client;
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

    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      _initialized = true;
      debugPrint('SupabaseService: hazır (${SupabaseConfig.url})');
    } catch (e, st) {
      debugPrint('SupabaseService.initialize başarısız: $e\n$st');
      rethrow;
    }
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
    return filterFreshVideos(posts);
  }

  /// Aşamalı arama: 500 → 1500 → 5000 → 20000 m; boşsa popüler fallback.
  ///
  /// [onProgress] her aşamada (yarıçap / fallback) UI’ya bildirir.
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
    Duration stageHold = const Duration(milliseconds: 420),
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

    if (cancelled()) {
      return NearbyFeedResult.empty(cancelled: true);
    }

    onProgress?.call(NearbyScanProgress.fallback());
    if (stageHold > Duration.zero) {
      await Future<void>.delayed(stageHold);
    }
    if (cancelled()) {
      return NearbyFeedResult.empty(cancelled: true);
    }

    final popular = await fetchPopularVideos(
      limit: SupabaseConfig.feedFallbackLimit,
    );
    if (cancelled()) {
      return NearbyFeedResult.empty(cancelled: true);
    }

    return NearbyFeedResult(
      posts: popular,
      matchedRadiusMeters: null,
      usedFallback: true,
    );
  }

  /// Konum filtresi yok — son 24 saatte en çok vibe alan videolar.
  Future<List<VibePost>> fetchPopularVideos({
    int limit = SupabaseConfig.feedFallbackLimit,
  }) async {
    _assertReady();

    final since = DateTime.now()
        .toUtc()
        .subtract(SupabaseConfig.videoTtl)
        .toIso8601String();

    final response = await client
        .from('videos')
        .select(
          'id, video_url, username, caption, subtitle, track_label, '
          'vibe_count, comment_count, created_at',
        )
        .gte('created_at', since)
        .order('vibe_count', ascending: false)
        .limit(limit);

    final rows = (response as List<dynamic>)
        .whereType<Map<Object?, Object?>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final posts = rows.map((row) {
      final mapped = Map<String, dynamic>.from(row);
      mapped.putIfAbsent('distance_m', () => null);
      mapped.putIfAbsent('score', () => null);
      final post = VibePost.fromRpc(mapped);
      return VibePost(
        id: post.id,
        videoUrl: post.videoUrl,
        username: post.username,
        caption: post.caption,
        distanceLabel: 'şehir vibe',
        subtitle: post.subtitle.isEmpty ? 'Popüler kaos' : post.subtitle,
        trackLabel: post.trackLabel,
        vibeCountLabel: post.vibeCountLabel,
        commentCountLabel: post.commentCountLabel,
        avatarColor: post.avatarColor,
        vibeCount: post.vibeCount,
        commentCount: post.commentCount,
        distanceMeters: null,
        score: post.score,
        createdAt: post.createdAt,
      );
    }).toList();

    return filterFreshVideos(posts);
  }

  /// 5 km içi aktif video kümeleri (trend / ısı listesi).
  Future<List<CampusHotspot>> fetchTrendingHotspots({
    required double latitude,
    required double longitude,
    double radiusMeters = SupabaseConfig.hotspotRadiusMeters,
    int limit = 20,
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

    return rows.map(CampusHotspot.fromRpc).toList(growable: false);
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

  /// Video 24 saatlik pencerede mi?
  bool isWithinTtl(DateTime createdAt, {DateTime? now}) {
    final anchor = (now ?? DateTime.now()).toUtc();
    final age = anchor.difference(createdAt.toUtc());
    return !age.isNegative && age <= SupabaseConfig.videoTtl;
  }

  /// Süresi dolmuş satır + storage temizliği (010 migration RPC).
  /// Hata olursa sessizce yutulur — feed’i bloklamaz.
  Future<int> purgeExpiredVideosBestEffort() async {
    if (!isReady) return 0;
    try {
      final result = await client.rpc('purge_expired_videos');
      if (result is int) return result;
      if (result is num) return result.toInt();
      return int.tryParse('$result') ?? 0;
    } catch (e, st) {
      debugPrint('SupabaseService.purgeExpiredVideosBestEffort: $e\n$st');
      return 0;
    }
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
  Future<VibePost> uploadVideo({
    required File file,
    required double latitude,
    required double longitude,
    required String username,
    required String deviceId,
    String caption = '',
    String subtitle = '',
    String trackLabel = 'original audio',
  }) async {
    _assertReady();

    if (!await file.exists()) {
      throw StateError('Video dosyası bulunamadı: ${file.path}');
    }

    final id = _uuid.v4();
    final ext = _extensionOf(file.path);
    final objectPath = '$deviceId/$id$ext';

    await client.storage.from(SupabaseConfig.videosBucket).upload(
          objectPath,
          file,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(ext),
            upsert: false,
          ),
        );

    final videoUrl =
        client.storage.from(SupabaseConfig.videosBucket).getPublicUrl(objectPath);

    // Point(lng, lat) PostGIS tarafında ST_MakePoint ile yazılır.
    final inserted = await client.rpc(
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
      },
    );

    final row = inserted is Map<String, dynamic>
        ? inserted
        : Map<String, dynamic>.from(
            (inserted as List<dynamic>).first as Map,
          );

    final createdAt =
        DateTime.tryParse('${row['created_at']}')?.toUtc() ??
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

  /// Vibe sayacını +1 (iyimser UI için).
  Future<void> incrementVibe(String videoId) async {
    _assertReady();
    await client.rpc('increment_vibe', params: {'p_video_id': videoId});
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
    if (isFallback) {
      return 'Yakınında kimse kalmamış ama şehirden kopan şu bombalara bir bak! 🔥';
    }
    switch (radiusMeters?.round()) {
      case 500:
        return 'Dip dibindeki kaos taranıyor... ⚡';
      case 1500:
        return 'Buralarda çıt çıkmıyor. Arama alanı mahalleye genişletiliyor... 😮';
      case 5000:
        return 'Kampüs uykuda gibi, tüm ilçedeki hareketliliğe bakılıyor... 💀';
      case 20000:
        return 'Tüm şehir taranıyor, vibe avı başladı! ⭐';
      default:
        return 'Nool Radar taranıyor...';
    }
  }
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
