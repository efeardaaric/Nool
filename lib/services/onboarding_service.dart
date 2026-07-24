import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Cihaz kimliği + `@anon_` kampüs lakabı (SharedPreferences).
class OnboardingService {
  OnboardingService._();

  static const _deviceIdKey = 'device_id';
  static const _usernameKey = 'username';
  static const _onboardedKey = 'nool_onboarded';
  static const _introSeenKey = 'nool_intro_seen';

  /// Eski anahtarlar — bir kez migrate edilir.
  static const _legacyDeviceIdKey = 'nool_device_id';
  static const _legacyUsernameKey = 'nool_username';

  static const _uuid = Uuid();

  /// Noktalamasız, goygoycu kampüs lakapları.
  static const _campusHandles = [
    'hazirlik_kacagi',
    'burslu_gocebe',
    'vizeler_yaklasirken',
    'kutuphane_hayaleti',
    'yemekhane_samurai',
    'gece_dersi_zombi',
    'cantasi_hep_agir',
    'wifi_avcisi',
    'quiz_kurtulan',
    'lab_saatinden_kacan',
    'yurt_koridoru',
    'kahve_borclu',
    'sunum_panik',
    'final_haftasi',
    'anon_rektorel',
    'kampus_glitch',
    'amfi_arka_sira',
    'odev_erteleme',
    'kantinci_efsane',
    'sabah_dersi_kayip',
  ];

  /// İlk açılışta kimlik + kullanıcı adı atar; sonraki açılışlarda mevcut değerleri döner.
  static Future<OnboardingResult> ensureOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyKeys(prefs);

    var deviceId = prefs.getString(_deviceIdKey);
    var username = prefs.getString(_usernameKey);

    if (deviceId == null || username == null) {
      deviceId = _uuid.v4();
      username = _generateUsername();
      await prefs.setString(_deviceIdKey, deviceId);
      await prefs.setString(_usernameKey, username);
      await prefs.setBool(_onboardedKey, true);
    }

    return OnboardingResult(deviceId: deviceId, username: username);
  }

  static Future<void> _migrateLegacyKeys(SharedPreferences prefs) async {
    final deviceId = prefs.getString(_deviceIdKey);
    final username = prefs.getString(_usernameKey);
    final legacyId = prefs.getString(_legacyDeviceIdKey);
    final legacyUser = prefs.getString(_legacyUsernameKey);

    if (deviceId == null && legacyId != null) {
      await prefs.setString(_deviceIdKey, legacyId);
    }
    if (username == null && legacyUser != null) {
      await prefs.setString(_usernameKey, legacyUser);
    }
  }

  static Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyKeys(prefs);
    return prefs.getString(_deviceIdKey);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyKeys(prefs);
    return prefs.getString(_usernameKey);
  }

  /// Eğitici karşılama turu görüldü mü / atlandı mı.
  static Future<bool> hasSeenIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_introSeenKey) ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
  }

  static String _generateUsername() {
    final rng = Random();
    final handle = _campusHandles[rng.nextInt(_campusHandles.length)];
    // Noktalama yok; yalnızca harf + alt çizgi.
    return '@anon_$handle';
  }
}

class OnboardingResult {
  const OnboardingResult({
    required this.deviceId,
    required this.username,
  });

  final String deviceId;
  final String username;
}
