import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/location_service.dart';
import '../services/onboarding_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'layout_manager.dart';

/// İlk temas: onboarding + konum + ana ekrana geçiş.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _panelController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _panelFade;
  late final Animation<Offset> _panelSlide;
  late final Animation<double> _pulse;

  String? _username;
  bool _booting = true;
  bool _showLocationPanel = false;
  bool _requestingPermission = false;
  String? _hintMessage;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _panelFade = CurvedAnimation(parent: _panelController, curve: Curves.easeOut);
    _panelSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic),
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
    _panelController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _booting = true;
      _showLocationPanel = false;
      _hintMessage = null;
    });

    final onboard = await OnboardingService.ensureOnboarded();
    if (!mounted) return;
    setState(() => _username = onboard.username);

    // Logo nefes alsın, sonra konum.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      await _revealLocationPanel(
        hint:
            'GPS kapalı gibi — kampüs radarımız kör. Konumu aç, kaos geri gelsin.',
      );
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await _goHomeWithLocation(onboard.username);
      return;
    }

    await _revealLocationPanel();
  }

  Future<void> _revealLocationPanel({String? hint}) async {
    setState(() {
      _booting = false;
      _showLocationPanel = true;
      _hintMessage = hint;
    });
    _panelController.forward(from: 0);
  }

  Future<void> _onRequestLocation() async {
    if (_requestingPermission) return;
    setState(() {
      _requestingPermission = true;
      _hintMessage = null;
    });

    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        setState(() {
          _hintMessage =
              'Konum servisi kapalı. Ayarlardan GPS’i aç, sonra tekrar dene — kaos bekler.';
        });
        await LocationService.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!mounted) return;

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final username =
            _username ?? await OnboardingService.getUsername() ?? '@anon';
        await _goHomeWithLocation(username);
        return;
      }

      setState(() {
        _hintMessage = permission == LocationPermission.deniedForever
            ? 'Kampüsteki kaosu görebilmen için konumuna ihtiyacımız var, ayarlardan manuel de açabilirsin.'
            : 'Kampüsteki kaosu görebilmen için konumuna ihtiyacımız var, ayarlardan manuel de açabilirsin.';
      });

      if (permission == LocationPermission.deniedForever) {
        await LocationService.openAppSettings();
      }
    } finally {
      if (mounted) setState(() => _requestingPermission = false);
    }
  }

  Future<void> _goHomeWithLocation(String username) async {
    setState(() {
      _booting = true;
      _showLocationPanel = false;
    });

    try {
      final position = await LocationService.getCurrentPosition();
      SupabaseService.instance.setSessionLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // İzin var ama GPS okunamadıysa yine ana ekrana geç; feed lokal demo’ya düşer.
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      noolRoute<void>(
        page: LayoutManager(username: username),
        duration: const Duration(milliseconds: 480),
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
          Positioned(
            bottom: -60,
            left: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NoolColors.lavender.withOpacity(0.10),
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
                  FadeTransition(
                    opacity: _logoFade,
                    child: Text(
                      'kampüs kaos, canlı',
                      style: GoogleFonts.syne(
                        color: NoolColors.lavender,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_booting && !_showLocationPanel) ...[
                    const NoolLottieView.loading(width: 72, height: 72),
                    const SizedBox(height: 12),
                    Text(
                      _username == null
                          ? 'anon kimlik fırınlanıyor…'
                          : 'merhaba $_username',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.syne(
                        color: NoolColors.lavender,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const Spacer(flex: 2),
                  if (_showLocationPanel)
                    FadeTransition(
                      opacity: _panelFade,
                      child: SlideTransition(
                        position: _panelSlide,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                          child: _LocationRequiredPanel(
                            username: _username,
                            hintMessage: _hintMessage,
                            requesting: _requestingPermission,
                            onRequest: _onRequestLocation,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 28),
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
          colors: [
            NoolColors.lavender,
            NoolColors.acid,
          ],
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

class _LocationRequiredPanel extends StatelessWidget {
  const _LocationRequiredPanel({
    required this.username,
    required this.hintMessage,
    required this.requesting,
    required this.onRequest,
  });

  final String? username;
  final String? hintMessage;
  final bool requesting;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.42),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: NoolColors.ink, width: 3.5),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Konum Gerekli!',
                style: GoogleFonts.syne(
                  color: NoolColors.acid,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                username == null
                    ? 'Yakındaki vibe’ları pinlemek için konumuna ihtiyacımız var.'
                    : '$username — kampüsteki kaosu pinlemek için konum lazım.',
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              if (hintMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  hintMessage!,
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              BrutalPressable(
                offset: const Offset(3, 3),
                onTap: requesting ? null : onRequest,
                enabled: !requesting,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: NoolColors.acid,
                    border: Border.all(color: NoolColors.ink, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: requesting
                      ? const NoolLottieView.loading(
                          width: 28,
                          height: 28,
                          compact: true,
                        )
                      : Text(
                          'Konum İznini Aç',
                          style: GoogleFonts.syne(
                            color: NoolColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
