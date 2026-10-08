/// In-app notification row (`public.notifications`).
class NoolNotification {
  const NoolNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    this.readAt,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;

  String? get actorId => data['actor_id']?.toString();
  String? get threadId => data['thread_id']?.toString();
  String? get groupId => data['group_id']?.toString();
  String? get squadId => data['squad_id']?.toString();

  /// Prefer EN copy from `data` for curiosity rows when locale is English.
  String displayTitle({required bool english}) {
    if (english && type == 'curiosity') {
      final en = data['en_title']?.toString();
      if (en != null && en.isNotEmpty) return en;
    }
    return title;
  }

  String displayBody({required bool english}) {
    if (english && type == 'curiosity') {
      final en = data['en_body']?.toString();
      if (en != null && en.isNotEmpty) return en;
    }
    return body;
  }

  factory NoolNotification.fromRow(Map<String, dynamic> row) {
    final dataRaw = row['data'];
    final data = dataRaw is Map
        ? Map<String, dynamic>.from(dataRaw)
        : <String, dynamic>{};

    DateTime? parseTs(Object? raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString())?.toUtc();
    }

    return NoolNotification(
      id: row['id'].toString(),
      userId: row['user_id'].toString(),
      type: (row['type'] as String?) ?? 'system',
      title: (row['title'] as String?) ?? 'Nool',
      body: (row['body'] as String?) ?? '',
      data: data,
      readAt: parseTs(row['read_at']),
      createdAt: parseTs(row['created_at']),
    );
  }
}
