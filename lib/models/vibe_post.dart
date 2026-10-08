import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Tek bir vibe (video) gönderisi.
class VibePost {
  const VibePost({
    required this.id,
    required this.videoUrl,
    required this.username,
    required this.caption,
    required this.distanceLabel,
    required this.subtitle,
    required this.trackLabel,
    required this.vibeCountLabel,
    required this.commentCountLabel,
    this.avatarColor = const Color(0xFFFF6F61),
    this.avatarUrl,
    this.vibeCount = 0,
    this.commentCount = 0,
    this.distanceMeters,
    this.score,
    this.createdAt,
    this.reactionCounts = const <String, int>{},
  });

  final String id;
  final String videoUrl;
  final String username;
  final String caption;
  final String distanceLabel;
  final String subtitle;
  final String trackLabel;
  final String vibeCountLabel;
  final String commentCountLabel;
  final Color avatarColor;

  /// `profiles.avatar_url` — feed’de yazar avatarı için (RPC sonrası enrich).
  final String? avatarUrl;

  final int vibeCount;
  final int commentCount;
  final double? distanceMeters;
  final double? score;
  final DateTime? createdAt;

  /// Aggregated emoji counts from `videos.reaction_counts` JSONB.
  /// Keys: laugh, pepper, smile, angry, star.
  final Map<String, int> reactionCounts;

  VibePost copyWith({
    String? id,
    String? videoUrl,
    String? username,
    String? caption,
    String? distanceLabel,
    String? subtitle,
    String? trackLabel,
    String? commentCountLabel,
    Color? avatarColor,
    String? avatarUrl,
    int? vibeCount,
    int? commentCount,
    double? distanceMeters,
    double? score,
    DateTime? createdAt,
    Map<String, int>? reactionCounts,
  }) {
    final nextVibes = vibeCount ?? this.vibeCount;
    final nextComments = commentCount ?? this.commentCount;
    return VibePost(
      id: id ?? this.id,
      videoUrl: videoUrl ?? this.videoUrl,
      username: username ?? this.username,
      caption: caption ?? this.caption,
      distanceLabel: distanceLabel ?? this.distanceLabel,
      subtitle: subtitle ?? this.subtitle,
      trackLabel: trackLabel ?? this.trackLabel,
      vibeCountLabel: _formatCount(nextVibes, suffix: ' Vibe'),
      commentCountLabel: commentCountLabel ?? _formatCount(nextComments),
      avatarColor: avatarColor ?? this.avatarColor,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      vibeCount: nextVibes,
      commentCount: nextComments,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      score: score ?? this.score,
      createdAt: createdAt ?? this.createdAt,
      reactionCounts: reactionCounts ?? this.reactionCounts,
    );
  }

  /// PostGIS RPC satırından model üretir.
  factory VibePost.fromRpc(Map<String, dynamic> row) {
    final distance = (row['distance_m'] as num?)?.toDouble();
    final vibes = (row['vibe_count'] as num?)?.toInt() ?? 0;
    final comments = (row['comment_count'] as num?)?.toInt() ?? 0;
    final createdRaw = row['created_at'];
    final createdAt = createdRaw == null
        ? null
        : DateTime.tryParse(createdRaw.toString())?.toUtc();

    return VibePost(
      id: row['id'].toString(),
      videoUrl: (row['video_url'] as String?) ?? '',
      username: (row['username'] as String?) ??
          AppStrings.fromSettings().anonymousHandle,
      caption: (row['caption'] as String?) ?? '',
      distanceLabel: _formatDistance(distance),
      subtitle: (row['subtitle'] as String?) ??
          (AppStrings.fromSettings().isEnglish ? 'Nearby' : 'Yakında'),
      trackLabel: (row['track_label'] as String?) ?? 'original audio',
      vibeCountLabel: _formatCount(vibes, suffix: ' Vibe'),
      commentCountLabel: _formatCount(comments),
      vibeCount: vibes,
      commentCount: comments,
      distanceMeters: distance,
      score: (row['score'] as num?)?.toDouble(),
      createdAt: createdAt,
      reactionCounts: parseReactionCounts(row['reaction_counts']),
      avatarUrl: row['avatar_url'] as String?,
    );
  }

  /// Parse `videos.reaction_counts` JSONB (Map or JSON string).
  static Map<String, int> parseReactionCounts(dynamic raw) {
    if (raw == null) return const {};
    Map<Object?, Object?> map;
    if (raw is Map) {
      map = Map<Object?, Object?>.from(raw);
    } else {
      return const {};
    }
    final out = <String, int>{};
    for (final entry in map.entries) {
      final key = entry.key?.toString();
      if (key == null || key.isEmpty) continue;
      final value = entry.value;
      final n = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '') ?? 0;
      if (n > 0) out[key] = n;
    }
    return Map<String, int>.unmodifiable(out);
  }

  static String _formatDistance(double? meters) {
    if (meters == null) return 'yakında';
    if (meters < 1000) return '${meters.round()}m yakınında';
    return '${(meters / 1000).toStringAsFixed(1)}km yakınında';
  }

  static String _formatCount(int value, {String suffix = ''}) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M$suffix';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k$suffix';
    }
    return '$value$suffix';
  }
}
