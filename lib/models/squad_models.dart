import 'user_profile.dart';

/// İki kullanıcı arasındaki squad durumu.
enum SquadConnectionStatus {
  notConnected,
  pendingSent,
  pendingReceived,
  accepted,
  rejected,
}

extension SquadConnectionStatusX on SquadConnectionStatus {
  String get apiLabel {
    switch (this) {
      case SquadConnectionStatus.notConnected:
        return 'not_connected';
      case SquadConnectionStatus.pendingSent:
        return 'pending_sent';
      case SquadConnectionStatus.pendingReceived:
        return 'pending_received';
      case SquadConnectionStatus.accepted:
        return 'accepted';
      case SquadConnectionStatus.rejected:
        return 'rejected';
    }
  }
}

/// Squad satırı (+ opsiyonel karşı profil).
class SquadEdge {
  const SquadEdge({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    this.createdAt,
    this.otherProfile,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final DateTime? createdAt;
  final UserProfile? otherProfile;

  factory SquadEdge.fromRow(
    Map<String, dynamic> row, {
    String? viewerId,
  }) {
    final createdRaw = row['created_at'];
    UserProfile? other;
    if (viewerId != null) {
      final sender = row['sender'];
      final receiver = row['receiver'];
      if (row['sender_id']?.toString() == viewerId && receiver is Map) {
        other = UserProfile.fromRow(Map<String, dynamic>.from(receiver));
      } else if (row['receiver_id']?.toString() == viewerId && sender is Map) {
        other = UserProfile.fromRow(Map<String, dynamic>.from(sender));
      }
    }

    return SquadEdge(
      id: row['id'].toString(),
      senderId: row['sender_id'].toString(),
      receiverId: row['receiver_id'].toString(),
      status: (row['status'] as String?) ?? 'pending',
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      otherProfile: other,
    );
  }
}
