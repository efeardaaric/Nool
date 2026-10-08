import 'user_profile.dart';

/// Kadro (squad circle) grubu.
class SquadGroup {
  const SquadGroup({
    required this.id,
    required this.name,
    this.createdBy,
    this.createdAt,
    this.memberCount,
    this.streak,
  });

  final String id;
  final String name;

  /// Kadro kurucusu — yalnızca bu kullanıcı silebilir.
  final String? createdBy;
  final DateTime? createdAt;
  final int? memberCount;
  final GroupStreak? streak;

  bool isOwnedBy(String? userId) =>
      userId != null && createdBy != null && createdBy == userId;

  factory SquadGroup.fromRow(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    GroupStreak? streak;
    final streakRaw = row['group_streaks'] ?? row['streak'];
    if (streakRaw is Map) {
      streak = GroupStreak.fromRow(Map<String, dynamic>.from(streakRaw));
    } else if (streakRaw is List && streakRaw.isNotEmpty) {
      final first = streakRaw.first;
      if (first is Map) {
        streak = GroupStreak.fromRow(Map<String, dynamic>.from(first));
      }
    }

    int? memberCount;
    final membersRaw = row['squad_group_members'] ?? row['members'];
    if (membersRaw is List) {
      memberCount = membersRaw.length;
    } else if (row['member_count'] != null) {
      memberCount = int.tryParse(row['member_count'].toString());
    }

    final ownerRaw = row['created_by'];
    return SquadGroup(
      id: row['id'].toString(),
      name: (row['name'] as String?)?.trim() ?? 'Kadro',
      createdBy: ownerRaw?.toString(),
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      memberCount: memberCount,
      streak: streak,
    );
  }
}

/// Grup video drop (24s TTL istemci tarafında).
class GroupDrop {
  const GroupDrop({
    required this.id,
    required this.groupId,
    required this.videoUrl,
    required this.caption,
    required this.senderId,
    this.storagePath,
    this.createdAt,
    this.senderUsername,
    this.senderAvatarUrl,
  });

  final String id;
  final String groupId;
  final String videoUrl;
  final String caption;
  final String senderId;
  final String? storagePath;
  final DateTime? createdAt;
  final String? senderUsername;
  final String? senderAvatarUrl;

  factory GroupDrop.fromRow(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    String? username;
    String? avatar;
    final sender = row['sender'] ?? row['profiles'];
    if (sender is Map) {
      final map = Map<String, dynamic>.from(sender);
      username = map['username'] as String?;
      avatar = map['avatar_url'] as String?;
    }

    return GroupDrop(
      id: row['id'].toString(),
      groupId: row['group_id'].toString(),
      videoUrl: (row['video_url'] as String?) ?? '',
      caption: (row['caption'] as String?) ?? '',
      senderId: row['sender_id'].toString(),
      storagePath: row['storage_path'] as String?,
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      senderUsername: username,
      senderAvatarUrl: avatar,
    );
  }
}

/// Kaos Ateşi streak durumu.
class GroupStreak {
  const GroupStreak({
    required this.id,
    required this.groupId,
    required this.currentStreak,
    this.lastDropAt,
    this.streakExpiryAt,
  });

  final String id;
  final String groupId;
  final int currentStreak;
  final DateTime? lastDropAt;
  final DateTime? streakExpiryAt;

  /// Sönmeye kalan süre (negatifse sönmüş).
  Duration? get timeUntilExpiry {
    final expiry = streakExpiryAt;
    if (expiry == null) return null;
    return expiry.difference(DateTime.now().toUtc());
  }

  int get hoursUntilExpiry {
    final d = timeUntilExpiry;
    if (d == null) return 0;
    if (d.isNegative) return 0;
    return d.inHours.clamp(0, 48);
  }

  /// Saatler düşüldükten sonra kalan dakika (0–59).
  int get minutesUntilExpiry {
    final d = timeUntilExpiry;
    if (d == null || d.isNegative) return 0;
    return d.inMinutes.remainder(60).clamp(0, 59);
  }

  /// `streak_expiry_at - now < 4h` → UI’da tangerine pulse.
  bool get isExpiringSoon {
    final d = timeUntilExpiry;
    if (d == null || d.isNegative) return false;
    return d < const Duration(hours: 4);
  }

  factory GroupStreak.fromRow(Map<String, dynamic> row) {
    final lastRaw = row['last_drop_at'];
    final expiryRaw = row['streak_expiry_at'];
    return GroupStreak(
      id: row['id']?.toString() ?? row['group_id'].toString(),
      groupId: row['group_id'].toString(),
      currentStreak: int.tryParse('${row['current_streak']}') ?? 0,
      lastDropAt: lastRaw == null
          ? null
          : DateTime.tryParse(lastRaw.toString())?.toUtc(),
      streakExpiryAt: expiryRaw == null
          ? null
          : DateTime.tryParse(expiryRaw.toString())?.toUtc(),
    );
  }
}

/// Grup sohbet mesajı.
class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.body,
    this.createdAt,
    this.sender,
  });

  final String id;
  final String groupId;
  final String senderId;
  final String body;
  final DateTime? createdAt;
  final UserProfile? sender;

  factory GroupMessage.fromRow(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    UserProfile? sender;
    final senderRaw = row['sender'] ?? row['profiles'];
    if (senderRaw is Map) {
      sender = UserProfile.fromRow(Map<String, dynamic>.from(senderRaw));
    }

    return GroupMessage(
      id: row['id'].toString(),
      groupId: row['group_id'].toString(),
      senderId: row['sender_id'].toString(),
      body: (row['body'] as String?) ?? '',
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      sender: sender,
    );
  }
}
