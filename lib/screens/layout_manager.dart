import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'camera_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';
import 'trending_hotspots_screen.dart';
import 'vibe_feed_screen.dart';

/// Ana iskelet: Akış · Kamera · Trend · Mesaj · Profil + floating brutalist nav.
class LayoutManager extends StatefulWidget {
  const LayoutManager({super.key, this.username});

  final String? username;

  @override
  State<LayoutManager> createState() => _LayoutManagerState();
}

class _LayoutManagerState extends State<LayoutManager> {
  static const _feedIndex = 0;
  static const _cameraIndex = 1;
  static const _trendIndex = 2;
  static const _messagesIndex = 3;
  static const _profileIndex = 4;

  final GlobalKey<VibeFeedScreenState> _feedKey =
      GlobalKey<VibeFeedScreenState>();
  final GlobalKey<_ProfileTabState> _profileTabKey =
      GlobalKey<_ProfileTabState>();

  int _index = 0;
  bool _ctaDismissed = false;
  bool _radarScanning = false;

  bool get _signedIn => AuthService().isSignedIn;

  bool get _showSecureCta =>
      !_signedIn && !_ctaDismissed && !_radarScanning && _index != _cameraIndex;

  void _onNavTap(int index) {
    if (index == _index) {
      if (index == _profileIndex) {
        _profileTabKey.currentState?.reload();
      }
      return;
    }
    setState(() => _index = index);
    if (index == _profileIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _profileTabKey.currentState?.reload();
      });
    }
  }

  void _exitCameraToFeed({bool refresh = false}) {
    setState(() => _index = _feedIndex);
    if (refresh) {
      _feedKey.currentState?.reloadFeed();
    }
  }

  Future<void> _openSignIn() async {
    final ok = await Navigator.of(context).push<bool>(
      noolRoute<bool>(page: const SignInScreen(popOnSuccess: true)),
    );
    if (!mounted) return;
    setState(() {});
    if (ok == true) {
      setState(() {
        _index = _profileIndex;
        _ctaDismissed = true;
      });
      _profileTabKey.currentState?.reload();
    }
  }

  void _goToProfileSecure() {
    setState(() => _index = _profileIndex);
  }

  @override
  Widget build(BuildContext context) {
    final feedActive = _index == _feedIndex;
    final cameraActive = _index == _cameraIndex;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NoolColors.night,
      extendBody: true,
      // Klavye / sheet nav'ı yukarı itmesin — floating nav sabit kalsın.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: [
              VibeFeedScreen(
                key: _feedKey,
                username: widget.username,
                isFeedActive: feedActive,
                showBottomNav: false,
                onRadarVisibilityChanged: (visible) {
                  // Yalnızca anon CTA için — nav asla radar yüzünden gizlenmez.
                  if (!mounted || _radarScanning == visible) return;
                  setState(() => _radarScanning = visible);
                },
              ),
              CameraScreen(
                isActive: cameraActive,
                onExit: () => _exitCameraToFeed(),
                onDropped: () => _exitCameraToFeed(refresh: true),
              ),
              TrendingHotspotsScreen(
                isActive: _index == _trendIndex,
                onHotspotSelected: (spot) {
                  setState(() => _index = _feedIndex);
                  _feedKey.currentState?.applyHotspotFilter(spot);
                },
              ),
              MessagesScreen(
                isActive: _index == _messagesIndex,
                onSecureAccount: _openSignIn,
              ),
              _ProfileTab(
                key: _profileTabKey,
                onSecureAccount: _openSignIn,
              ),
            ],
          ),
          if (_showSecureCta)
            Positioned(
              left: 16,
              right: 16,
              // Nav yüksekliği + bottom gap + CTA–nav boşluğu (safe area ayrı).
              bottom: bottomPad + _BrutalFloatingNav.height + 24,
              child: _SecureAccountCta(
                onSecure: _openSignIn,
                onOpenProfile: _goToProfileSecure,
                onDismiss: () => setState(() => _ctaDismissed = true),
              ),
            ),
          // Floating nav her zaman görünür (radar / feed yüklemesi gizlemez).
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 12,
            child: AnimatedBuilder(
              animation: SettingsService.instance,
              builder: (context, _) {
                return _BrutalFloatingNav(
                  currentIndex: _index,
                  signedIn: _signedIn,
                  onTap: _onNavTap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Profil sekmesi — giriş yoksa gate, varsa gömülü ProfileScreen.
class _ProfileTab extends StatefulWidget {
  const _ProfileTab({super.key, required this.onSecureAccount});

  final Future<void> Function() onSecureAccount;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  int _tick = 0;

  void reload() => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    // _tick force rebuild after auth.
    final signedIn = AuthService().isSignedIn;
    if (!signedIn) {
      return _AnonProfileGate(
        key: ValueKey('anon-$_tick'),
        onSecureAccount: widget.onSecureAccount,
      );
    }
    return ProfileScreen(
      key: ValueKey('profile-$_tick'),
      embedded: true,
    );
  }
}

class _AnonProfileGate extends StatelessWidget {
  const _AnonProfileGate({super.key, required this.onSecureAccount});

  final Future<void> Function() onSecureAccount;

  @override
  Widget build(BuildContext context) {
    return NoolAtmosphere(
      accent: AtmosphereAccent.acid,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoolPulse(
                min: 0.98,
                max: 1.02,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const NoolLogoMark(size: 36, border: true, shadow: true),
                    const SizedBox(width: 10),
                    Text(
                      'NOOL',
                      style: GoogleFonts.syne(
                        color: NoolColors.acid,
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              const Center(
                child: NoolLottieView.success(width: 120, height: 120),
              ),
              const SizedBox(height: 8),
              const Center(
                child: NoolIcon(
                  NoolIconData.person,
                  color: NoolColors.acid,
                  size: 48,
                  withBrutalShadow: true,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.s.secureAccountTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.s.secureAccountBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const Spacer(flex: 2),
              BrutalPressable(
                offset: const Offset(5, 5),
                onTap: () => onSecureAccount(),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NoolColors.acid,
                    border: Border.all(color: NoolColors.ink, width: 3.5),
                  ),
                  child: Text(
                    context.s.secureAccountCta,
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => onSecureAccount(),
                child: Text(
                  context.s.signInOrSignUp,
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w700,
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

/// Floating nav üstünde anon CTA şeridi.
class _SecureAccountCta extends StatelessWidget {
  const _SecureAccountCta({
    required this.onSecure,
    required this.onOpenProfile,
    required this.onDismiss,
  });

  final VoidCallback onSecure;
  final VoidCallback onOpenProfile;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return BrutalPressable(
      offset: const Offset(4, 4),
      onTap: onSecure,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: NoolColors.acid,
          border: Border.all(color: NoolColors.ink, width: 3),
        ),
        child: Row(
          children: [
            const NoolIcon(
              NoolIconData.person,
              color: NoolColors.ink,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.s.secureAccountBannerTitle,
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    context.s.secureAccountBannerHint,
                    style: GoogleFonts.syne(
                      color: NoolColors.ink.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onOpenProfile,
              tooltip: context.s.navProfile,
              icon: const NoolIcon(
                NoolIconData.personOutline,
                color: NoolColors.ink,
                size: 18,
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: context.s.dismissTooltip,
              icon: const NoolIcon(
                NoolIconData.close,
                color: NoolColors.ink,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrutalFloatingNav extends StatelessWidget {
  const _BrutalFloatingNav({
    required this.currentIndex,
    required this.signedIn,
    required this.onTap,
  });

  /// İç padding + ikon/etiket + 3px acid border için güvenli yükseklik.
  /// 68, seçili kutu padding’i ve Syne etiket metriklerinde 1px taşıyordu.
  static const double height = 72;

  final int currentIndex;
  final bool signedIn;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    // Sabit yükseklik zorunlu: Positioned(left/right/bottom) maxHeight ≈ ekran;
    // CrossAxisAlignment.stretch o yüzden nav’ı tam ekran şişirip Impeller’da
    // BackdropFilter’ı görünmez bırakıyordu.
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: NoolColors.night.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: NoolColors.acid, width: 3),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.homeOutline,
                  activeIcon: NoolIconData.home,
                  label: s.navFeed,
                  selected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
              ),
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.cameraOutline,
                  activeIcon: NoolIconData.camera,
                  label: s.navCamera,
                  selected: currentIndex == 1,
                  accent: true,
                  onTap: () => onTap(1),
                ),
              ),
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.fireOutline,
                  activeIcon: NoolIconData.fire,
                  label: s.navTrend,
                  selected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ),
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.send,
                  activeIcon: NoolIconData.send,
                  label: s.navMessages,
                  selected: currentIndex == 3,
                  onTap: () => onTap(3),
                ),
              ),
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.personOutline,
                  activeIcon: NoolIconData.person,
                  label: signedIn ? s.navProfile : s.navAccount,
                  selected: currentIndex == 4,
                  highlight: !signedIn,
                  onTap: () => onTap(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = false,
    this.highlight = false,
  });

  final NoolIconData icon;
  final NoolIconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool accent;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // Seçili: yalnızca büyük ikon @ asit kutu (etiket yok — 5 sekmede taşmayı önler).
    // Değil: asit/tangerine ikon + etiket — koyu videoda kaybolmasın.
    final labelColor = highlight ? NoolColors.tangerine : NoolColors.acid;
    final iconColor = selected
        ? NoolColors.ink
        : (highlight ? NoolColors.tangerine : NoolColors.acid);
    // Seçili: etiket yok + ~%20 büyük ikon. Değil: ikon + etiket.
    final size = selected ? (accent ? 26.0 : 24.0) : 22.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.symmetric(
          vertical: selected ? 4 : 2,
          horizontal: selected ? 4 : 0,
        ),
        decoration: BoxDecoration(
          color: selected ? NoolColors.acid : Colors.transparent,
          border: Border.all(
            color: selected ? NoolColors.ink : Colors.transparent,
            width: selected ? 3 : 0,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: selected
            ? AnimatedScale(
                scale: 1.2,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: NoolIcon(
                  activeIcon,
                  color: iconColor,
                  size: size,
                  withBrutalShadow: false,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NoolIcon(
                    icon,
                    color: iconColor,
                    size: size,
                    withBrutalShadow: false,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.syne(
                        color: labelColor,
                        fontSize: 10,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
