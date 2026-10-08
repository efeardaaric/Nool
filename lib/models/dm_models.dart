import 'user_profile.dart';

/// 1:1 DM thread between two users.
class DmThread {
  const DmThread({
    required this.id,
    required this.participantA,
    required this.participantB,
    this.createdAt,
    this.updatedAt,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.otherProfile,
  });

  final String id;
  final String participantA;
  final String participantB;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final UserProfile? otherProfile;

  String otherUserId(String myId) {
    if (participantA == myId) return participantB;
    return participantA;
  }

  factory DmThread.fromRow(
    Map<String, dynamic> row, {
    String? viewerId,
    UserProfile? otherProfile,
  }) {
    final createdRaw = row['created_at'];
    final updatedRaw = row['updated_at'];
    final lastRaw = row['last_message_at'];

    UserProfile? other = otherProfile;
    if (other == null && viewerId != null) {
      final a = row['participant_a_profile'] ?? row['a_profile'];
      final b = row['participant_b_profile'] ?? row['b_profile'];
      final aId = row['participant_a']?.toString();
      final bId = row['participant_b']?.toString();
      if (aId == viewerId && b is Map) {
        other = UserProfile.fromRow(Map<String, dynamic>.from(b));
      } else if (bId == viewerId && a is Map) {
        other = UserProfile.fromRow(Map<String, dynamic>.from(a));
      }
    }

    return DmThread(
      id: row['id'].toString(),
      participantA: row['participant_a'].toString(),
      participantB: row['participant_b'].toString(),
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      updatedAt: updatedRaw == null
          ? null
          : DateTime.tryParse(updatedRaw.toString())?.toUtc(),
      lastMessageAt: lastRaw == null
          ? null
          : DateTime.tryParse(lastRaw.toString())?.toUtc(),
      lastMessagePreview: row['last_message_preview'] as String?,
      otherProfile: other,
    );
  }
}

/// Single DM message in a thread.
class DmMessage {
  const DmMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    this.createdAt,
    this.sender,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String body;
  final DateTime? createdAt;
  final UserProfile? sender;

  factory DmMessage.fromRow(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    UserProfile? sender;
    final senderRaw = row['sender'] ?? row['profiles'];
    if (senderRaw is Map) {
      sender = UserProfile.fromRow(Map<String, dynamic>.from(senderRaw));
    }

    return DmMessage(
      id: row['id'].toString(),
      threadId: row['thread_id'].toString(),
      senderId: row['sender_id'].toString(),
      body: (row['body'] as String?) ?? '',
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      sender: sender,
    );
  }
}
