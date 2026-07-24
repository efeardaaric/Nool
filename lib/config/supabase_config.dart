/// Supabase bağlantı bilgileri (Nool projesi).
abstract final class SupabaseConfig {
  static const String url = 'https://tytgkikirhxvhzveyimi.supabase.co';

  /// Dashboard → API → anon (JWT) public key.
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR5dGdraWtpcmh4dmh6dmV5aW1pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MDIyNjQsImV4cCI6MjEwMDQ3ODI2NH0.bt99tqdYsbYo8Ibfmx908O0xqYemDibAeLSVgQf_jd4';

  static String get publishableKey => anonKey;

  static bool get isConfigured => true;

  static const videosBucket = 'campus-drops';
  static const avatarsBucket = 'avatars';
  static const legacyVideosBucket = 'videos';
  static const feedRpc = 'get_nearby_videos';
  static const hotspotsRpc = 'get_trending_hotspots';
  static const videoTtl = Duration(hours: 24);
  static const hotspotRadiusMeters = 5000.0;
  static const feedSearchRadiiMeters = <double>[500, 1500, 5000, 20000];
  static const feedFallbackLimit = 10;
}
