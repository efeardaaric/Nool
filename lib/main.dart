import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Avatar / thumbnail bellek baskısını sınırla (feed + profil).
  PaintingBinding.instance.imageCache.maximumSize = 120;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20; // 48 MB
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: NoolColors.night,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await SupabaseService.instance.initialize();

  runApp(const NoolApp());
}

class NoolApp extends StatelessWidget {
  const NoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nool',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
