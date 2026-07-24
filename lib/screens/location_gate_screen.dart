import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/onboarding_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';
import 'layout_manager.dart';

/// Auth sonrası konum izni → ana shell.
class LocationGateScreen extends StatefulWidget {
  const LocationGateScreen({super.key});

  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

class _LocationGateScreenState extends State<LocationGateScreen> {
  bool _requesting = false;
  bool _booting = true;
  String? _hint;
  String? _username;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final name = AuthService().displayName ??
        await OnboardingService.getUsername() ??
        '@nool';
    if (!mounted) return;
    setState(() => _username = name);

    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      setState(() {
        _booting = false;
        _hint =
            'GPS kapalı gibi — kampüs radarımız kör. Konumu aç, kaos geri gelsin.';
      });
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await _enterApp();
      return;
    }

    if (!mounted) return;
    setState(() => _booting = false);
  }

  Future<void> _request() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _hint = null;
    });

    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        setState(() {
          _hint =
              'Konum servisi kapalı. Ayarlardan GPS’i aç, sonra tekrar dene.';
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
        await _enterApp();
        return;
      }

      setState(() {
        _hint =
            'Kampüsteki kaosu görebilmen için konumuna ihtiyacımız var. '
            'Ayarlardan manuel de açabilirsin.';
      });
      if (permission == LocationPermission.deniedForever) {
        await LocationService.openAppSettings();
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _enterApp() async {
    setState(() => _booting = true);
    try {
      final position = await LocationService.getCurrentPosition();
      SupabaseService.instance.setSessionLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {}

    final username = _username ??
        AuthService().displayName ??
        await OnboardingService.getUsername() ??
        '@nool';

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      noolRoute<void>(
        page: LayoutManager(username: username),
        duration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.acid,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                if (_booting) ...[
                  const Center(
                    child: NoolLottieView.loading(width: 72, height: 72),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'konum sabitleniyor…',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                    decoration: BoxDecoration(
                      color: const Color(0xE60D0A1C),
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
                      children: [
                        Text(
                          'Konum Gerekli!',
                          style: GoogleFonts.syne(
                            color: NoolColors.acid,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _username == null
                              ? 'Yakındaki vibe’ları pinlemek için konumuna ihtiyacımız var.'
                              : '$_username — kampüsteki kaosu pinlemek için konum lazım.',
                          style: GoogleFonts.syne(
                            color: NoolColors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                        if (_hint != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _hint!,
                            style: GoogleFonts.syne(
                              color: NoolColors.lavender,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        BrutalPressable(
                          onTap: _requesting ? null : _request,
                          enabled: !_requesting,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: NoolColors.acid,
                              border: Border.all(
                                color: NoolColors.ink,
                                width: 3,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: _requesting
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
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
