import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../theme/colors.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// FCM background isolate stub — keep top-level + `@pragma`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background / terminated: OS shows the system tray notification.
  // Extend later for data-only payloads (local notification, deep link, etc.).
  debugPrint(
    'FCM background: ${message.messageId} '
    'title=${message.notification?.title}',
  );
}

/// Firebase Cloud Messaging + profiles.fcm_token (singleton).
///
/// Firebase config (GoogleService-Info.plist / google-services.json) yoksa
/// uygulama çökmez — initialize no-op + log.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// MaterialApp.navigatorKey — foreground acid banner overlay.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// MaterialApp.scaffoldMessengerKey — SnackBar fallback.
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _initialized = false;
  bool _firebaseReady = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  OverlayEntry? _bannerEntry;

  bool get isReady => _firebaseReady;

  /// Firebase + FCM listeners. Hata → log, app start devam eder.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e, st) {
      debugPrint(
        'NotificationService: Firebase init failed (config missing?). '
        'Push no-op. $e\n$st',
      );
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: true,
      );

      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        unawaited(_persistToken(token));
      });

      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Zaten oturum açıksa token'ı kaydet (izin varsa).
      unawaited(registerToken());
    } catch (e, st) {
      debugPrint('NotificationService: FCM wiring failed: $e\n$st');
    }
  }

  /// OS bildirim izni + Gen-Z neo-brutal onay diyaloğu.
  ///
  /// Caller (splash / settings / post-login) context ile çağırır.
  Future<bool> requestPermissionWithPrompt(BuildContext context) async {
    if (!_firebaseReady) {
      debugPrint('NotificationService.requestPermission: Firebase not ready');
      return false;
    }

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final s = AppStrings.of(ctx);
        return AlertDialog(
          backgroundColor: NoolColors.night,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NoolColors.acid, width: 3.5),
          ),
          title: Text(
            s.pushPermissionTitle,
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.5,
            ),
          ),
          content: Text(
            s.pushPermissionBody,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w600,
              height: 1.4,
              fontSize: 15,
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                s.pushPermissionLater,
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Material(
              color: NoolColors.acid,
              child: InkWell(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: NoolColors.ink, width: 3.5),
                    boxShadow: const [
                      BoxShadow(
                        color: NoolColors.ink,
                        offset: Offset(4, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Text(
                    s.pushPermissionAllow,
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (proceed != true) return false;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (granted) {
      await registerToken();
    }
    return granted;
  }

  /// FCM token al → `profiles.fcm_token` güncelle (signed-in + Firebase ready).
  Future<void> registerToken() async {
    if (!_firebaseReady) return;
    if (!SupabaseService.instance.isReady) return;
    final uid = AuthService().currentUser?.id;
    if (uid == null) return;

    try {
      var settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('NotificationService.registerToken: permission denied');
        return;
      }

      // iOS: ilk seferde sistem izni (Gen-Z dialog için requestPermissionWithPrompt).
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final granted =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
        if (!granted) return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('NotificationService.registerToken: empty token');
        return;
      }
      await _persistToken(token);
    } catch (e, st) {
      debugPrint('NotificationService.registerToken: $e\n$st');
    }
  }

  Future<void> _persistToken(String token) async {
    if (!SupabaseService.instance.isReady) return;
    final uid = AuthService().currentUser?.id;
    if (uid == null) return;

    try {
      await SupabaseService.instance.client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', uid);
      debugPrint('NotificationService: fcm_token saved for $uid');
    } catch (e, st) {
      debugPrint('NotificationService._persistToken: $e\n$st');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Nool';
    final body =
        message.notification?.body ?? message.data['body']?.toString() ?? '';
    showAcidBanner(title: title, body: body);
  }

  /// Neo-brutal acid in-app banner (foreground). SnackBar fallback.
  void showAcidBanner({
    required String title,
    required String body,
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.acid,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NoolColors.ink, width: 3),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.syne(
                  color: NoolColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.syne(
                    color: NoolColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      return;
    }

    _bannerEntry?.remove();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final top = MediaQuery.paddingOf(context).top + 12;
        return Positioned(
          top: top,
          left: 16,
          right: 16,
          child: _AcidPushBanner(
            title: title,
            body: body,
            onDismiss: () {
              entry.remove();
              if (_bannerEntry == entry) _bannerEntry = null;
            },
          ),
        );
      },
    );
    _bannerEntry = entry;
    overlay.insert(entry);

    Future<void>.delayed(const Duration(seconds: 4), () {
      if (_bannerEntry == entry) {
        entry.remove();
        _bannerEntry = null;
      }
    });
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    _bannerEntry?.remove();
    _bannerEntry = null;
  }
}

class _AcidPushBanner extends StatefulWidget {
  const _AcidPushBanner({
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  final String title;
  final String body;
  final VoidCallback onDismiss;

  @override
  State<_AcidPushBanner> createState() => _AcidPushBannerState();
}

class _AcidPushBannerState extends State<_AcidPushBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: NoolColors.acid,
                border: Border.all(color: NoolColors.ink, width: 3.5),
                boxShadow: const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(5, 5),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.syne(
                            color: NoolColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                        if (widget.body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.syne(
                              color: NoolColors.night,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '✕',
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
