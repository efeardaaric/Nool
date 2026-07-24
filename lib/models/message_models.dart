import 'user_profile.dart';

/// Inbox satırı — list_my_conversations RPC.
class ConversationPreview {
  const ConversationPreview({
    required this.conversationId,
    required this.otherUserId,
    required this.otherUsername,
    this.otherAvatarUrl,
    this.lastMessageAt,
    this.lastMessagePreview = '',
    this.createdAt,
  });

  final String conversationId;
  final String otherUserId;
  final String otherUsername;
  final String? otherAvatarUrl;
  final DateTime? lastMessageAt;
  final String lastMessagePreview;
  final DateTime? createdAt;

  String get displayName {
    final n = otherUsername;
    return n.startsWith('@') ? n : '@$n';
  }

  factory ConversationPreview.fromRow(Map<String, dynamic> row) {
    final lastRaw = row['last_message_at'];
    final createdRaw = row['created_at'];
    return ConversationPreview(
      conversationId: row['conversation_id'].toString(),
      otherUserId: row['other_user_id'].toString(),
      otherUsername: (row['other_username'] as String?) ?? '@anon',
      otherAvatarUrl: row['other_avatar_url'] as String?,
      lastMessageAt: lastRaw == null
          ? null
          : DateTime.tryParse(lastRaw.toString())?.toUtc(),
      lastMessagePreview: (row['last_message_preview'] as String?) ?? '',
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
    );
  }

  UserProfile get otherAsProfile => UserProfile(
        id: otherUserId,
        username: otherUsername,
        avatarUrl: otherAvatarUrl,
      );
}

/// Tek DM mesajı.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    this.createdAt,
    this.readAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool isMine(String? myId) => myId != null && senderId == myId;

  factory ChatMessage.fromRow(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    final readRaw = row['read_at'];
    return ChatMessage(
      id: row['id'].toString(),
      conversationId: row['conversation_id'].toString(),
      senderId: row['sender_id'].toString(),
      body: (row['body'] as String?) ?? '',
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      readAt: readRaw == null
          ? null
          : DateTime.tryParse(readRaw.toString())?.toUtc(),
    );
  }
}

/// Canlı sosyal bildirim türü.
enum SocialEventType {
  squadRequest,
  squadAccepted,
  newMessage,
}

class SocialEvent {
  const SocialEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.relatedUserId,
    this.relatedUsername,
    this.conversationId,
    this.requestId,
  });

  final String id;
  final SocialEventType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? relatedUserId;
  final String? relatedUsername;
  final String? conversationId;
  final String? requestId;
}
