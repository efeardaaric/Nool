import '../l10n/app_strings.dart';

class CommentItem {
  const CommentItem({
    required this.id,
    required this.videoId,
    required this.deviceId,
    required this.username,
    required this.body,
    required this.createdAt,
    this.avatarUrl,
  });

  final String id;
  final String videoId;
  final String deviceId;
  final String username;
  final String body;
  final DateTime createdAt;
  final String? avatarUrl;

  factory CommentItem.fromRow(Map<String, dynamic> row) {
    return CommentItem(
      id: row['id'].toString(),
      videoId: row['video_id'].toString(),
      deviceId: (row['device_id'] as String?) ?? '',
      username: (row['username'] as String?) ??
          AppStrings.fromSettings().anonymousHandle,
      body: (row['body'] as String?) ?? '',
      createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
          DateTime.now(),
      avatarUrl: row['avatar_url'] as String?,
    );
  }

  CommentItem copyWith({String? avatarUrl}) {
    return CommentItem(
      id: id,
      videoId: videoId,
      deviceId: deviceId,
      username: username,
      body: body,
      createdAt: createdAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 45) return 'şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk';
    if (diff.inHours < 24) return '${diff.inHours}sa';
    return '${diff.inDays}g';
  }
}
