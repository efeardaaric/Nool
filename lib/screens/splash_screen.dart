import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'intro_screen.dart';
import 'location_gate_screen.dart';
import 'sign_in_screen.dart';

/// İlk temas: logo → (intro) → auth zorunlu → konum → ana shell.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _pulse;

  String? _status;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _pulse = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _logoController.forward();
    _bootstrap();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _status = 'hazırlanıyor…');

    await OnboardingService.ensureOnboarded();
    if (!mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;

    final seenIntro = await OnboardingService.hasSeenIntro();
    if (!mounted) return;

    if (!seenIntro) {
      _pulseController.stop();
      Navigator.of(context).pushReplacement(
        noolRoute<void>(
          page: const IntroScreen(),
          duration: const Duration(milliseconds: 280),
        ),
      );
      return;
    }

    if (!AuthService().isSignedIn) {
      _pulseController.stop();
      Navigator.of(context).pushReplacement(
        noolRoute<void>(
          page: const SignInScreen(gateMode: true),
          duration: const Duration(milliseconds: 280),
        ),
      );
      return;
    }

    _pulseController.stop();
    Navigator.of(context).pushReplacement(
      noolRoute<void>(
        page: const LocationGateScreen(),
        duration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NoolColors.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const NoolAtmosphere(accent: AtmosphereAccent.acid),
          const NoolScanLines(opacity: 0.035),
          Positioned(
            top: -100,
            right: -80,
            child: ScaleTransition(
              scale: _pulse,
              child: NoolDrift(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NoolColors.acid.withOpacity(0.10),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _logoFade,
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  ScaleTransition(
                    scale: _logoScale,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NoolLogoMark(size: 148),
                        SizedBox(height: 20),
                        _NoolWordmark(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'kampüs kaos, canlı',
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const NoolLottieView.loading(width: 72, height: 72),
                  const SizedBox(height: 12),
                  Text(
                    _status ?? '',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoolWordmark extends StatelessWidget {
  const _NoolWordmark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NoolColors.lavender, NoolColors.acid],
        ).createShader(bounds);
      },
      child: Text(
        'NOOL',
        textAlign: TextAlign.center,
        style: GoogleFonts.syne(
          fontSize: 56,
          fontWeight: FontWeight.w800,
          height: 0.95,
          letterSpacing: -2.5,
          color: Colors.white,
        ),
      ),
    );
  }
}
