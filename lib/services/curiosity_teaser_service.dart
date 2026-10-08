import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'auth_service.dart';
import 'curiosity_teaser_copy.dart';
import 'settings_service.dart';
import 'supabase_service.dart';

/// Local curiosity teasers + last-active heartbeat for server FCM cron.
///
/// Caps: ≤1 local teaser / ~22h; evening slot ~19:30; gated by
/// Settings **Merak bildirimleri**.
class CuriosityTeaserService {
  CuriosityTeaserService._();
  static final CuriosityTeaserService instance = CuriosityTeaserService._();

  static const _channelId = 'nool_curiosity';
  static const _channelName = 'Nool Merak';
  static const _notifId = 7701;
  static const _lastOpenKey = 'nool_curiosity_last_open_ms';
  static const _lastScheduledKey = 'nool_curiosity_last_scheduled_ms';
  static const _minGapBetweenLocal = Duration(hours: 22);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;

    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (e) {
        debugPrint('CuriosityTeaserService timezone: $e');
        tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      }

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      if (!kIsWeb && Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Merak / re-engagement teasers',
            importance: Importance.defaultImportance,
          ),
        );
      }

      _ready = true;
    } catch (e, st) {
      debugPrint('CuriosityTeaserService.initialize: $e\n$st');
    }

    unawaited(onAppBecameActive());
  }

  /// Call from [WidgetsBindingObserver.didChangeAppLifecycleState] / sign-in.
  Future<void> onAppBecameActive() async {
    await markActive();
    await rescheduleIfNeeded();
  }

  Future<void> markActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastOpenKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    if (!SupabaseService.instance.isReady) return;
    if (AuthService().currentUser == null) return;
    try {
      await SupabaseService.instance.client.rpc('touch_last_active');
    } catch (e) {
      debugPrint('CuriosityTeaserService.touch_last_active: $e');
    }
  }

  Future<void> syncCuriosityPref(bool enabled) async {
    if (!SupabaseService.instance.isReady) return;
    if (AuthService().currentUser == null) return;
    try {
      await SupabaseService.instance.client.rpc(
        'set_curiosity_push_enabled',
        params: {'p_enabled': enabled},
      );
    } catch (e) {
      debugPrint('CuriosityTeaserService.syncCuriosityPref: $e');
    }
  }

  Future<void> onCuriosityPrefChanged(bool enabled) async {
    await syncCuriosityPref(enabled);
    if (!enabled) {
      await cancelScheduled();
    } else {
      await rescheduleIfNeeded(force: true);
    }
  }

  Future<void> cancelScheduled() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_notifId);
    } catch (e) {
      debugPrint('CuriosityTeaserService.cancel: $e');
    }
  }

  Future<void> rescheduleIfNeeded({bool force = false}) async {
    if (!_ready) return;
    if (!SettingsService.instance.curiosityPushOn) {
      await cancelScheduled();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastScheduledMs = prefs.getInt(_lastScheduledKey);

    if (lastScheduledMs != null && !force) {
      final scheduledAt = DateTime.fromMillisecondsSinceEpoch(lastScheduledMs);
      // Already have a future slot — keep it.
      if (scheduledAt.isAfter(now.add(const Duration(minutes: 30)))) {
        return;
      }
      final since = now.difference(scheduledAt);
      if (since < _minGapBetweenLocal && scheduledAt.isBefore(now)) {
        // Fired recently — wait out cooldown before next evening.
        return;
      }
    }

    await _scheduleNextEvening(prefs, now);
  }

  Future<void> _scheduleNextEvening(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    try {
      final english = SettingsService.instance.isEnglish;
      final copy = randomCuriosityTeaser(Random().nextInt(1 << 31));
      final when = _nextQuietEvening(
        now,
        lastOpenMs: prefs.getInt(_lastOpenKey),
      );

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Merak / re-engagement teasers',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _plugin.zonedSchedule(
        _notifId,
        copy.title(english),
        copy.body(english),
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'curiosity:${copy.kind}',
      );

      await prefs.setInt(_lastScheduledKey, when.millisecondsSinceEpoch);
      debugPrint(
        'CuriosityTeaserService: scheduled ${copy.kind} at $when',
      );
    } catch (e, st) {
      debugPrint('CuriosityTeaserService.schedule: $e\n$st');
    }
  }

  /// ~19:30 local (+ jitter). If past today's slot or user is warm → tomorrow.
  DateTime _nextQuietEvening(DateTime now, {int? lastOpenMs}) {
    var target = DateTime(now.year, now.month, now.day, 19, 30);
    if (!now.isBefore(target.subtract(const Duration(minutes: 5)))) {
      target = target.add(const Duration(days: 1));
    } else if (lastOpenMs != null) {
      final sinceOpen =
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastOpenMs));
      // Still in-session / recently opened → don't tease tonight.
      if (sinceOpen < const Duration(hours: 12) &&
          target.difference(now) < const Duration(hours: 14)) {
        target = target.add(const Duration(days: 1));
      }
    }
    final jitterMin = Random().nextInt(40);
    return target.add(Duration(minutes: jitterMin));
  }
}
