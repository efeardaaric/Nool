import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/reset_password_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/curiosity_teaser_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/social_notification_service.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: NoolColors.night,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const NoolBootstrap());
}

Future<void> initializeNool() async {
  await Future.wait([
    SupabaseService.instance.initialize(),
    SettingsService.instance.load(),
  ]);

  // Firebase config yoksa no-op — app start'ı bloklamaz.
  try {
    await NotificationService.instance.initialize();
  } catch (e, st) {
    debugPrint('main: NotificationService init skipped: $e\n$st');
  }

  try {
    await CuriosityTeaserService.instance.initialize();
  } catch (e, st) {
    debugPrint('main: CuriosityTeaserService init skipped: $e\n$st');
  }

  if (AuthService().isSignedIn) {
    unawaited(SocialNotificationService.instance.startWatching());
  }
}

/// Render immediately and let the user retry a failed startup.
class NoolBootstrap extends StatefulWidget {
  const NoolBootstrap({super.key, this.initialize = initializeNool});

  final Future<void> Function() initialize;

  @override
  State<NoolBootstrap> createState() => _NoolBootstrapState();
}

class _NoolBootstrapState extends State<NoolBootstrap> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = widget.initialize();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError) {
            return const NoolApp();
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: NoolColors.night,
              body: SafeArea(
                child: Center(
                  child: snapshot.hasError
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Nool başlatılamadı. Lütfen tekrar deneyin.\n'
                                'Nool could not start. Please try again.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => setState(() {
                                  _initialization = widget.initialize();
                                }),
                                child: const Text('Yeniden dene / Retry'),
                              ),
                            ],
                          ),
                        )
                      : const CircularProgressIndicator(color: NoolColors.acid),
                ),
              ),
            ),
          );
        },
      );
}

class NoolApp extends StatefulWidget {
  const NoolApp({super.key});

  @override
  State<NoolApp> createState() => _NoolAppState();
}

class _NoolAppState extends State<NoolApp> with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _recoverySub;
  bool _openingReset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (SupabaseService.instance.isReady) {
      _recoverySub = AuthService().listenPasswordRecovery(_openResetPassword);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recoverySub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(CuriosityTeaserService.instance.onAppBecameActive());
    }
  }

  void _openResetPassword() {
    if (_openingReset) return;
    _openingReset = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = NotificationService.instance.navigatorKey.currentState;
      if (nav == null) {
        _openingReset = false;
        return;
      }
      nav
          .push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const ResetPasswordScreen(),
            ),
          )
          .whenComplete(() => _openingReset = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final notifications = NotificationService.instance;

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Nool',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          navigatorKey: notifications.navigatorKey,
          scaffoldMessengerKey: notifications.scaffoldMessengerKey,
          locale: settings.locale,
          supportedLocales: SettingsService.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SplashScreen(),
        );
      },
    );
  }
}
