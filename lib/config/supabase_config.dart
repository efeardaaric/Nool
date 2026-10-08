/// Supabase bağlantı bilgileri.
///
/// Varsayılanlar Nool projesine bağlıdır. Geçersiz kılmak için:
/// ```
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ydqhmlqdyuybwmxskbsn.supabase.co',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_kNWQZOoUniEobmTNSy9Vzw_dHEFQSBM',
  );

  /// Supabase dashboard "publishable" / anon anahtarı.
  static String get publishableKey => anonKey;

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static const videosBucket = 'campus-drops';

  /// Kadro grup video drop’ları.
  static const groupDropsBucket = 'group-drops';

  /// Profil avatarları.
  static const avatarsBucket = 'avatars';

  /// Eski alias — geriye dönük referanslar için.
  static const legacyVideosBucket = 'videos';
  static const feedRpc = 'get_nearby_videos';
  static const hotspotsRpc = 'get_trending_hotspots';
  static const videoTtl = Duration(hours: 24);

  /// Yoğunluk halkaları (metre): 500m → 1 → 2 → 3 → 5 → 10 → 20 km.
  static const densityRadiiMeters = <double>[
    500,
    1000,
    2000,
    3000,
    5000,
    10000,
    20000,
  ];

  /// Trend varsayılan halkası — seyrekse istemci bir üst halkaya çıkar.
  static const hotspotRadiusMeters = 500.0;

  /// Bu kadar video yoksa bir sonraki yoğunluk halkasına genişle.
  static const densityMinVideos = 6;

  /// Hotspot pininden izlerken küme yarıçapı (metre).
  static const hotspotClusterRadiusMeters = 320.0;

  /// Near You / Trend izleme: yalnızca yoğunluk halkaları (worldwide yok).
  static const feedSearchRadiiMeters = densityRadiiMeters;

  /// Campus / vibing vb. fallback limitleri.
  static const feedFallbackLimit = 60;
}
