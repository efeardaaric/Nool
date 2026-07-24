import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../icons/nool_icons.dart';
import '../services/auth_service.dart';
import '../services/social_notification_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/social_banner_host.dart';
import 'camera_screen.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';
import 'trending_hotspots_screen.dart';
import 'vibe_feed_screen.dart';

/// Ana iskelet: Akış · Kamera · Trend · Profil + floating brutalist nav.
/// Hesapsız kullanım yok — oturum düşerse girişe zorlanır.
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

  StreamSubscription<AuthState>? _authSub;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (!AuthService().isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _forceSignIn());
    } else if (SupabaseService.instance.isReady) {
      SocialNotificationService().start();
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.session == null && mounted) {
          SocialNotificationService().stop();
          _forceSignIn();
        } else if (data.session != null) {
          SocialNotificationService().start();
        }
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _forceSignIn() {
    Navigator.of(context).pushAndRemoveUntil(
      noolRoute<void>(
        page: const SignInScreen(gateMode: true),
        duration: const Duration(milliseconds: 280),
      ),
      (_) => false,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final feedActive = _index == _feedIndex;
    final cameraActive = _index == _cameraIndex;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NoolColors.night,
      extendBody: true,
      body: SocialBannerHost(
        child: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(
              index: _index,
              sizing: StackFit.expand,
              children: [
                TickerMode(
                  enabled: feedActive,
                  child: VibeFeedScreen(
                    key: _feedKey,
                    username: widget.username,
                    isFeedActive: feedActive,
                    showBottomNav: false,
                  ),
                ),
                TickerMode(
                  enabled: cameraActive,
                  child: CameraScreen(
                    isActive: cameraActive,
                    onExit: () => _exitCameraToFeed(),
                    onDropped: () => _exitCameraToFeed(refresh: true),
                  ),
                ),
                TickerMode(
                  enabled: _index == _trendIndex,
                  child: TrendingHotspotsScreen(
                    isActive: _index == _trendIndex,
                    onHotspotSelected: (spot) {
                      setState(() => _index = _feedIndex);
                      _feedKey.currentState?.applyHotspotFilter(spot);
                    },
                  ),
                ),
                TickerMode(
                  enabled: _index == _profileIndex,
                  child: _ProfileTab(key: _profileTabKey),
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomPad + 12,
              child: _BrutalFloatingNav(
                currentIndex: _index,
                onTap: _onNavTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({super.key});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  int _tick = 0;

  void reload() => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    return ProfileScreen(
      key: ValueKey('profile-$_tick'),
      embedded: true,
    );
  }
}

class _BrutalFloatingNav extends StatelessWidget {
  const _BrutalFloatingNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: NoolColors.night.withOpacity(0.96),
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
              label: 'Profil',
              selected: currentIndex == 3,
              onTap: () => onTap(3),
            ),
          ),
        ],
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
  });

  final NoolIconData icon;
  final NoolIconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = selected ? NoolColors.ink : NoolColors.white;
    final size = accent && selected ? 24.0 : 22.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
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
                color: color,
                size: size,
                withBrutalShadow: false,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.syne(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
