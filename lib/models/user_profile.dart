/// public.profiles satırı.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.bio = '',
    this.avatarUrl,
    this.createdAt,
  });

  final String id;
  final String username;
  final String bio;
  final String? avatarUrl;
  final DateTime? createdAt;

  factory UserProfile.fromRow(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    return UserProfile(
      id: row['id'].toString(),
      username: (row['username'] as String?) ?? '@anon',
      bio: (row['bio'] as String?) ?? '',
      avatarUrl: row['avatar_url'] as String?,
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
    );
  }

  UserProfile copyWith({
    String? username,
    String? bio,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
    );
  }
}
