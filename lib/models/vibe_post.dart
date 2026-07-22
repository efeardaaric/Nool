import 'package:flutter/material.dart';

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
    this.vibeCount = 0,
    this.commentCount = 0,
    this.distanceMeters,
    this.score,
    this.createdAt,
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

  final int vibeCount;
  final int commentCount;
  final double? distanceMeters;
  final double? score;
  final DateTime? createdAt;

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
      username: (row['username'] as String?) ?? '@anon',
      caption: (row['caption'] as String?) ?? '',
      distanceLabel: _formatDistance(distance),
      subtitle: (row['subtitle'] as String?) ?? 'Yakındaki kaos',
      trackLabel: (row['track_label'] as String?) ?? 'original audio',
      vibeCountLabel: _formatCount(vibes, suffix: ' Vibe'),
      commentCountLabel: _formatCount(comments),
      vibeCount: vibes,
      commentCount: comments,
      distanceMeters: distance,
      score: (row['score'] as num?)?.toDouble(),
      createdAt: createdAt,
    );
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
