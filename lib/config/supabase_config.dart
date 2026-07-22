/// Supabase bağlantı bilgileri.
///
/// Çalıştırırken:
/// ```
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Supabase dashboard "publishable" / anon anahtarı.
  static String get publishableKey => anonKey;

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static const videosBucket = 'campus-drops';
  /// Profil avatarları.
  static const avatarsBucket = 'avatars';
  /// Eski alias — geriye dönük referanslar için.
  static const legacyVideosBucket = 'videos';
  static const feedRpc = 'get_nearby_videos';
  static const hotspotsRpc = 'get_trending_hotspots';
  static const videoTtl = Duration(hours: 24);
  static const hotspotRadiusMeters = 5000.0;

  /// Dinamik arama çapı: kampüs → semt → ilçe → şehir (metre).
  static const feedSearchRadiiMeters = <double>[500, 1500, 5000, 20000];
  static const feedFallbackLimit = 10;
}
