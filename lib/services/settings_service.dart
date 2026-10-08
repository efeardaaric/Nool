import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama ayarları — dil, ses varsayılanı, haptic vb.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _localeKey = 'nool_locale';
  static const _feedSoundKey = 'nool_feed_sound_on';
  static const _hapticsKey = 'nool_haptics_on';
  static const _reduceMotionKey = 'nool_reduce_motion';
  static const _curiosityPushKey = 'nool_curiosity_push_on';

  Locale _locale = const Locale('tr');
  bool _feedSoundOn = true;
  bool _hapticsOn = true;
  bool _reduceMotion = false;
  bool _curiosityPushOn = true;
  bool _ready = false;

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isEnglish => languageCode == 'en';
  bool get feedSoundOn => _feedSoundOn;
  bool get hapticsOn => _hapticsOn;
  bool get reduceMotion => _reduceMotion;
  bool get curiosityPushOn => _curiosityPushOn;
  bool get ready => _ready;

  static const supportedLocales = <Locale>[
    Locale('tr'),
    Locale('en'),
  ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code == 'en' || code == 'tr') {
      _locale = Locale(code!);
    }
    _feedSoundOn = prefs.getBool(_feedSoundKey) ?? true;
    _hapticsOn = prefs.getBool(_hapticsKey) ?? true;
    _reduceMotion = prefs.getBool(_reduceMotionKey) ?? false;
    _curiosityPushOn = prefs.getBool(_curiosityPushKey) ?? true;
    _ready = true;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode != 'tr' && locale.languageCode != 'en') return;
    if (_locale.languageCode == locale.languageCode) return;
    _locale = Locale(locale.languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, _locale.languageCode);
    notifyListeners();
  }

  Future<void> setFeedSoundOn(bool value) async {
    if (_feedSoundOn == value) return;
    _feedSoundOn = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_feedSoundKey, value);
    notifyListeners();
  }

  Future<void> setHapticsOn(bool value) async {
    if (_hapticsOn == value) return;
    _hapticsOn = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticsKey, value);
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reduceMotionKey, value);
    notifyListeners();
  }

  Future<void> setCuriosityPushOn(bool value) async {
    if (_curiosityPushOn == value) return;
    _curiosityPushOn = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_curiosityPushKey, value);
    notifyListeners();
  }
}
