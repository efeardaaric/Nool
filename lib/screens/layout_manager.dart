import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../services/auth_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'camera_screen.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';
import 'trending_hotspots_screen.dart';
import 'vibe_feed_screen.dart';

/// Ana iskelet: Akış · Kamera · Trend · Profil + floating brutalist nav.
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
  static const _profileIndex = 3;

  final GlobalKey<VibeFeedScreenState> _feedKey =
      GlobalKey<VibeFeedScreenState>();
  final GlobalKey<_ProfileTabState> _profileTabKey =
      GlobalKey<_ProfileTabState>();

  int _index = 0;
  bool _ctaDismissed = false;

  bool get _signedIn => AuthService().isSignedIn;

  bool get _showSecureCta =>
      !_signedIn && !_ctaDismissed && _index != _cameraIndex;

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
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NoolColors.night,
      extendBody: true,
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
              bottom: bottomPad + 88,
              child: _SecureAccountCta(
                onSecure: _openSignIn,
                onOpenProfile: _goToProfileSecure,
                onDismiss: () => setState(() => _ctaDismissed = true),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 12,
            child: _BrutalFloatingNav(
              currentIndex: _index,
              signedIn: _signedIn,
              onTap: _onNavTap,
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
                'Hâlâ anon’sun.',
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
                'Drop’ların ve squad’ların kalıcı olsun. '
                'Hesabını güvenceye al — 2 saniye.',
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
                    'HESABIMI GÜVENCEYE AL',
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
                  'Giriş Yap / Kayıt Ol',
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
                    'Hesabımı güvenceye al',
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Anonim kalma — kalıcı kaos için tap.',
                    style: GoogleFonts.syne(
                      color: NoolColors.ink.withOpacity(0.75),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onOpenProfile,
              tooltip: 'Profil',
              icon: const NoolIcon(
                NoolIconData.personOutline,
                color: NoolColors.ink,
                size: 18,
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Kapat',
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

  final int currentIndex;
  final bool signedIn;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: NoolColors.lavender.withOpacity(0.10),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: NoolColors.ink, width: 3),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.homeOutline,
                  activeIcon: NoolIconData.home,
                  label: 'Akış',
                  selected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
              ),
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.cameraOutline,
                  activeIcon: NoolIconData.camera,
                  label: 'Kamera',
                  selected: currentIndex == 1,
                  accent: true,
                  onTap: () => onTap(1),
                ),
              ),
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.fireOutline,
                  activeIcon: NoolIconData.fire,
                  label: 'Trend',
                  selected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ),
              Expanded(
                child: _NavEntry(
                  icon: NoolIconData.personOutline,
                  activeIcon: NoolIconData.person,
                  label: signedIn ? 'Profil' : 'Hesap',
                  selected: currentIndex == 3,
                  highlight: !signedIn,
                  onTap: () => onTap(3),
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
    final color = selected
        ? NoolColors.ink
        : (highlight ? NoolColors.tangerine : NoolColors.white);
    final iconColor = selected
        ? NoolColors.ink
        : (highlight ? NoolColors.tangerine : NoolColors.white);
    final size = accent && selected ? 26.0 : 22.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NoolColors.acid : Colors.transparent,
          border: Border.all(
            color: selected ? NoolColors.ink : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.06 : 1,
              duration: const Duration(milliseconds: 180),
              child: NoolIcon(
                selected ? activeIcon : icon,
                color: iconColor,
                size: size,
                withBrutalShadow: false,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.syne(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
