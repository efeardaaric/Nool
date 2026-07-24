import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'location_gate_screen.dart';
import 'sign_in_screen.dart';

/// İlk açılışta uygulamayı tanıtan eğitici tur (atlanabilir).
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_IntroPageData>[
    _IntroPageData(
      title: 'Kampüs, canlı',
      body:
          'Nool, etrafındaki kısa vibe’ları haritada değil — '
          'yakınlık skoruna göre akışta gösterir. Ne kadar yakınsa, o kadar önde.',
      accent: AtmosphereAccent.acid,
      icon: NoolIconData.home,
      lottie: _IntroLottie.radar,
    ),
    _IntroPageData(
      title: '15 saniyelik kaos',
      body:
          'Kamerayla kısa drop bırak. İstersen Gizem Modu ile yüzünü ve '
          'mekanı bulandır — anonim kal, vibe’ı bırak.',
      accent: AtmosphereAccent.tangerine,
      icon: NoolIconData.camera,
      lottie: _IntroLottie.camera,
    ),
    _IntroPageData(
      title: 'Trend & vibe',
      body:
          'Hotspot’larda biriken drop’ları keşfet, vibe bas, yorum at. '
          'Hesabınla profilin ve squad’ın kalıcı olur.',
      accent: AtmosphereAccent.lavender,
      icon: NoolIconData.fire,
      lottie: _IntroLottie.fire,
    ),
  ];

  Future<void> _finish() async {
    await OnboardingService.markIntroSeen();
    if (!mounted) return;

    if (!AuthService().isSignedIn) {
      Navigator.of(context).pushReplacement(
        noolRoute<void>(
          page: const SignInScreen(gateMode: true),
          duration: const Duration(milliseconds: 280),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      noolRoute<void>(
        page: const LocationGateScreen(),
        duration: const Duration(milliseconds: 280),
      ),
    );
  }

  void _next() {
    if (_page >= _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: page.accent,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    const NoolLogoMark(size: 36, border: true, shadow: false),
                    const SizedBox(width: 10),
                    Text(
                      'NOOL',
                      style: GoogleFonts.syne(
                        color: NoolColors.acid,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        'Atla',
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, index) {
                    final data = _pages[index];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
                      child: Column(
                        children: [
                          const Spacer(flex: 1),
                          _IntroVisual(data: data),
                          const Spacer(flex: 1),
                          Text(
                            data.title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.syne(
                              color: NoolColors.acid,
                              fontWeight: FontWeight.w800,
                              fontSize: 32,
                              height: 1.05,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            data.body,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.syne(
                              color: NoolColors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                          const Spacer(flex: 2),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: active ? 28 : 8,
                          decoration: BoxDecoration(
                            color: active
                                ? NoolColors.acid
                                : NoolColors.lavender.withOpacity(0.35),
                            border: Border.all(
                              color: NoolColors.ink,
                              width: active ? 2 : 0,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    BrutalPressable(
                      onTap: _next,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: NoolColors.acid,
                          border: Border.all(color: NoolColors.ink, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          isLast ? 'Hadi başlayalım' : 'Devam',
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
          ),
        ),
      ),
    );
  }
}

enum _IntroLottie { radar, camera, fire }

class _IntroPageData {
  const _IntroPageData({
    required this.title,
    required this.body,
    required this.accent,
    required this.icon,
    required this.lottie,
  });

  final String title;
  final String body;
  final AtmosphereAccent accent;
  final NoolIconData icon;
  final _IntroLottie lottie;
}

class _IntroVisual extends StatelessWidget {
  const _IntroVisual({required this.data});

  final _IntroPageData data;

  @override
  Widget build(BuildContext context) {
    final Widget media = switch (data.lottie) {
      _IntroLottie.radar => const NoolLottieView.radar(width: 180, height: 180),
      _IntroLottie.camera =>
        const NoolLottieView.loading(width: 120, height: 120),
      _IntroLottie.fire =>
        const NoolLottieView.fire(width: 160, height: 160, energy: true),
    };

    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: NoolColors.night.withOpacity(0.55),
        border: Border.all(color: NoolColors.ink, width: 3.5),
        boxShadow: const [
          BoxShadow(
            color: NoolColors.ink,
            offset: Offset(5, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          media,
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NoolColors.acid,
                border: Border.all(color: NoolColors.ink, width: 2.5),
              ),
              child: NoolIcon(
                data.icon,
                color: NoolColors.ink,
                size: 22,
                withBrutalShadow: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
