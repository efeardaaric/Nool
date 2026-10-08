import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/location_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import 'layout_manager.dart';
import 'splash_screen.dart';

/// Konum izni reddedilince — asit yeşili uyarı kompozisyonu.
class PermissionDeniedScreen extends StatefulWidget {
  const PermissionDeniedScreen({super.key});

  @override
  State<PermissionDeniedScreen> createState() => _PermissionDeniedScreenState();
}

class _PermissionDeniedScreenState extends State<PermissionDeniedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    final granted = await LocationService.requestPermission();
    if (!mounted) return;

    if (granted) {
      final username = await _resolveUsername();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LayoutManager(username: username),
        ),
      );
      return;
    }

    await LocationService.openAppSettings();
  }

  Future<String> _resolveUsername() async {
    return await OnboardingService.getUsername() ??
        AppStrings.fromSettings().anonymousHandle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  NoolColors.night,
                  Color.lerp(NoolColors.night, NoolColors.acid, 0.12)!,
                  NoolColors.night,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -40,
            left: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NoolColors.acid.withValues(alpha: 0.15),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      Text(
                        'Nool',
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: NoolColors.acid,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const Spacer(flex: 2),
                      Text(
                        context.s.trendStop,
                        style:
                            Theme.of(context).textTheme.displayLarge?.copyWith(
                                  fontSize: 64,
                                  height: 0.95,
                                  color: NoolColors.acid,
                                ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.s.permissionDeniedHeadline,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                  color: NoolColors.white,
                                ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.s.permissionDeniedBody,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 16,
                              height: 1.45,
                              color: NoolColors.lavender,
                            ),
                      ),
                      const Spacer(flex: 3),
                      BrutalShadow(
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _retry,
                            child: Text(context.s.retryPermission),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      BrutalShadow(
                        offset: const Offset(3, 3),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SplashScreen(),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: NoolColors.acid,
                              side: const BorderSide(
                                color: NoolColors.acid,
                                width: 3.5,
                              ),
                            ),
                            child: Text(context.s.backToStart),
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
