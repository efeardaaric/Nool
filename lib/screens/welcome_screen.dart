import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../services/onboarding_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';

/// İlk açılış welcome — 3 kısa sayfa, atlanabilir.
/// Kimlik onboarding'den bağımsız; [OnboardingService.markWelcomeSeen].
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  static const _pageCount = 3;

  final _pageController = PageController();
  int _index = 0;
  bool _finishing = false;

  late final AnimationController _enterController;
  late final AnimationController _visualController;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;
  late final Animation<double> _visualScale;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _visualController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _enterFade = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOut,
    );
    _enterSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic),
    );
    _visualScale = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _visualController, curve: Curves.easeInOut),
    );

    _enterController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _enterController.dispose();
    _visualController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await OnboardingService.markWelcomeSeen();
    if (!mounted) return;
    widget.onFinished();
  }

  void _onContinue() {
    if (_index >= _pageCount - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  AtmosphereAccent get _accent {
    return switch (_index) {
      0 => AtmosphereAccent.acid,
      1 => AtmosphereAccent.tangerine,
      _ => AtmosphereAccent.lavender,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            child: NoolAtmosphere(
              key: ValueKey(_accent),
              accent: _accent,
            ),
          ),
          const NoolScanLines(opacity: 0.03),
          SafeArea(
            child: FadeTransition(
              opacity: _enterFade,
              child: SlideTransition(
                position: _enterSlide,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                      child: Row(
                        children: [
                          const Spacer(),
                          TextButton(
                            onPressed: _finishing ? null : _finish,
                            style: TextButton.styleFrom(
                              foregroundColor: NoolColors.lavender,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              s.welcomeSkip,
                              style: GoogleFonts.syne(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (i) => setState(() => _index = i),
                        children: [
                          _WelcomePage(
                            visual: ScaleTransition(
                              scale: _visualScale,
                              child: const NoolLogoMark(size: 132),
                            ),
                            brandFirst: true,
                            headline: s.welcomePage1Headline,
                            body: s.welcomePage1Body,
                          ),
                          _WelcomePage(
                            visual: ScaleTransition(
                              scale: _visualScale,
                              child: const _LoopVisual(),
                            ),
                            brandFirst: false,
                            headline: s.welcomePage2Headline,
                            body: s.welcomePage2Body,
                          ),
                          _WelcomePage(
                            visual: ScaleTransition(
                              scale: _visualScale,
                              child: const _StartVisual(),
                            ),
                            brandFirst: false,
                            headline: s.welcomePage3Headline,
                            body: s.welcomePage3Body,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(22, 8, 22, 16 + bottomPad),
                      child: Column(
                        children: [
                          _SquarePageDots(
                            count: _pageCount,
                            index: _index,
                          ),
                          const SizedBox(height: 18),
                          BrutalPressable(
                            offset: const Offset(3, 3),
                            onTap: _finishing ? null : _onContinue,
                            enabled: !_finishing,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: _index == _pageCount - 1
                                    ? NoolColors.acid
                                    : NoolColors.white,
                                border: Border.all(
                                  color: NoolColors.ink,
                                  width: 3,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _index == _pageCount - 1
                                    ? s.welcomeStartCta
                                    : s.welcomeContinue,
                                style: GoogleFonts.syne(
                                  color: NoolColors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: 0.4,
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
          ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({
    required this.visual,
    required this.brandFirst,
    required this.headline,
    required this.body,
  });

  final Widget visual;
  final bool brandFirst;
  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          visual,
          const SizedBox(height: 28),
          if (brandFirst) ...[
            ShaderMask(
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
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  height: 0.95,
                  letterSpacing: -2.2,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 22,
                height: 1.15,
              ),
            ),
          ] else ...[
            Text(
              headline,
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.acid,
                fontWeight: FontWeight.w800,
                fontSize: 30,
                height: 1.1,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.syne(
              color: NoolColors.lavender,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

/// Yakın + kamera döngüsü — kart değil, tek kompozisyon.
class _LoopVisual extends StatelessWidget {
  const _LoopVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const NoolLottieView.radar(width: 200, height: 200),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: NoolColors.tangerine,
                border: Border.all(color: NoolColors.ink, width: 3.5),
                boxShadow: const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const NoolIcon(
                NoolIconData.camera,
                size: 30,
                color: NoolColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartVisual extends StatelessWidget {
  const _StartVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      height: 148,
      decoration: BoxDecoration(
        color: NoolColors.acid,
        border: Border.all(color: NoolColors.ink, width: 4),
        boxShadow: const [
          BoxShadow(
            color: NoolColors.ink,
            offset: Offset(5, 5),
            blurRadius: 0,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const NoolLottieView.fire(width: 88, height: 88, energy: true),
    );
  }
}

/// Neo-brutal kare page dots — soft pill yok.
class _SquarePageDots extends StatelessWidget {
  const _SquarePageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 22 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active
                ? NoolColors.acid
                : NoolColors.lavender.withValues(alpha: 0.35),
            border: Border.all(color: NoolColors.ink, width: 2),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: NoolColors.ink,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
