import '../l10n/app_strings.dart';

/// public.profiles satırı.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.bio = '',
    this.avatarUrl,
    this.createdAt,
    this.studentEmail,
    this.emailDomain,
    this.universityId,
  });

  final String id;
  final String username;
  final String bio;
  final String? avatarUrl;
  final DateTime? createdAt;

  /// Öğrenci e-postası (kampüs üyeliği).
  final String? studentEmail;

  /// `student_email` domain’i — Campus feed anahtarı.
  final String? emailDomain;

  /// Geriye uyum: genelde [emailDomain] ile aynı.
  final String? universityId;

  /// Kampüs feed’ine erişim — domain bağlı.
  bool get hasCampusAccess {
    final d = (emailDomain ?? universityId)?.trim();
    return d != null && d.isNotEmpty;
  }

  String? get campusDomain {
    final d = (emailDomain ?? universityId)?.trim();
    if (d == null || d.isEmpty) return null;
    return d.toLowerCase();
  }

  factory UserProfile.fromRow(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    String? trimOrNull(dynamic v) {
      final s = (v as String?)?.trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    return UserProfile(
      id: row['id'].toString(),
      username: (row['username'] as String?) ??
          AppStrings.fromSettings().anonymousHandle,
      bio: (row['bio'] as String?) ?? '',
      avatarUrl: row['avatar_url'] as String?,
      createdAt: createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw.toString())?.toUtc(),
      studentEmail: trimOrNull(row['student_email'])?.toLowerCase(),
      emailDomain: trimOrNull(row['email_domain'])?.toLowerCase(),
      universityId: trimOrNull(row['university_id'])?.toLowerCase(),
    );
  }

  UserProfile copyWith({
    String? username,
    String? bio,
    String? avatarUrl,
    String? studentEmail,
    String? emailDomain,
    String? universityId,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      studentEmail: studentEmail ?? this.studentEmail,
      emailDomain: emailDomain ?? this.emailDomain,
      universityId: universityId ?? this.universityId,
    );
  }
}
