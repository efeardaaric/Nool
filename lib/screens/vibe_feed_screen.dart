import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../config/supabase_config.dart';
import '../icons/nool_emojis.dart';
import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../models/campus_hotspot.dart';
import '../models/vibe_post.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/onboarding_service.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/claim_student_email_sheet.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_cover_video.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'other_profile_screen.dart';
import 'people_search_screen.dart';
import 'sign_in_screen.dart';

/// TikTok tarzı dikey vibe video akışı.
class VibeFeedScreen extends StatefulWidget {
  const VibeFeedScreen({
    super.key,
    this.username,
    this.isFeedActive = true,
    this.showBottomNav = false,
    this.onRadarVisibilityChanged,
  });

  final String? username;

  /// LayoutManager kamera/trend sekmesindeyken false — videolar pause.
  final bool isFeedActive;

  /// LayoutManager kendi nav’ını gösteriyorsa false.
  final bool showBottomNav;

  /// Radar tam ekran iken alt nav’ı gizlemek için.
  final ValueChanged<bool>? onRadarVisibilityChanged;

  @override
  State<VibeFeedScreen> createState() => VibeFeedScreenState();
}

class VibeFeedScreenState extends State<VibeFeedScreen> {
  static const _tabNearYou = 0;
  static const _tabVibing = 1;
  static const _tabCampus = 2;

  late final PageController _pageController;
  late List<VibePost> _posts;

  int _currentIndex = 0;

  /// 0 Near You · 1 Vibing · 2 Campus
  int _activeTab = _tabNearYou;
  int _navIndex = 1;
  final Set<String> _vibedIds = {};

  /// In-flight vibe toggles — ignore overlapping taps per video.
  final Set<String> _vibeInFlight = {};
  HotspotFeedFilter? _hotspotFilter;

  /// Current page’s info card expanded — locks vertical PageView physics.
  bool _infoExpanded = false;

  /// Artan id — eski async yüklemeleri yok saymak için.
  int _loadGeneration = 0;
  bool _radarVisible = false;
  NearbyScanProgress? _scanProgress;

  /// Campus boşken toast’ı bir kez göster.
  bool _campusEmptyToasted = false;

  /// Campus: öğrenci maili yok → claim gate.
  bool _campusNeedsEmail = false;
  String? _campusDomain;

  /// Normalized local username for “own post” checks in more-menu.
  String? _myUsernameNorm;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Supabase hazırsa demo kullanıcı gösterme — gerçek feed beklenir.
    // Always growable — hide/report mutates via removeAt/removeWhere.
    // Release: asla demo içerik gösterme — boş liste + radar/empty state.
    _posts = <VibePost>[];
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: NoolColors.ink,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _resolveMyUsername();
    _loadFeed();
  }

  @override
  void didUpdateWidget(covariant VibeFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _resolveMyUsername();
    }
  }

  Future<void> _resolveMyUsername() async {
    final fromWidget = SupabaseService.normalizeUsername(widget.username);
    if (fromWidget != null) {
      if (mounted) setState(() => _myUsernameNorm = fromWidget);
      return;
    }
    final local = await OnboardingService.getUsername();
    final norm = SupabaseService.normalizeUsername(local);
    if (!mounted) return;
    setState(() => _myUsernameNorm = norm);
  }

  bool _isOwnPost(VibePost post) {
    final mine = _myUsernameNorm;
    final theirs = SupabaseService.normalizeUsername(post.username);
    return mine != null && theirs != null && mine == theirs;
  }

  Future<void> reloadFeed() => _loadFeed();

  /// Trend ekranından gelen konum filtresi — yalnızca hotspot kümesi + vicinity.
  Future<void> applyHotspotFilter(CampusHotspot hotspot) async {
    setState(() {
      _hotspotFilter = HotspotFeedFilter(
        latitude: hotspot.latitude,
        longitude: hotspot.longitude,
        name: hotspot.name,
        radiusMeters: SupabaseConfig.hotspotClusterRadiusMeters,
        vicinityRadiusMeters: hotspot.vicinityRadiusMeters,
      );
      _activeTab = _tabNearYou;
    });
    await _loadFeed();
  }

  Future<void> clearHotspotFilter() async {
    setState(() => _hotspotFilter = null);
    await _loadFeed();
  }

  Future<void> _onTabSelected(int index) async {
    if (index == _activeTab) return;
    // Aktif sayfa videolarını durdur — posts temizlenince _VibePage dispose.
    setState(() {
      _activeTab = index;
      _hotspotFilter = null;
      _posts = <VibePost>[];
      _currentIndex = 0;
      _infoExpanded = false;
      _campusEmptyToasted = false;
      _campusNeedsEmail = false;
      _campusDomain = null;
    });
    await _loadFeed();
  }

  Future<void> _loadFeed() async {
    final supabase = SupabaseService.instance;
    if (!supabase.isReady) return;

    final generation = ++_loadGeneration;
    bool isStale() => !mounted || generation != _loadGeneration;
    final tab = _activeTab;

    _setRadarVisible(true);
    setState(() {
      _scanProgress = NearbyScanProgress.radius(radiusMeters: 500);
    });

    try {
      List<VibePost> remote = const [];
      var usedFallback = false;
      var campusUnavailable = false;
      var campusNeedsEmail = false;
      String? campusDomain;

      if (tab == _tabVibing) {
        if (mounted && !isStale()) {
          setState(() {
            _scanProgress = NearbyScanProgress.fallback();
          });
        }
        remote = await supabase.fetchVibingVideos();
        if (isStale()) return;
      } else if (tab == _tabCampus) {
        if (mounted && !isStale()) {
          setState(() {
            _scanProgress = NearbyScanProgress.fallback();
          });
        }
        if (!AuthService().isSignedIn) {
          campusNeedsEmail = true;
          remote = const [];
        } else {
          final campus = await supabase.fetchCampusFeed();
          if (isStale()) return;
          remote = campus.posts;
          campusNeedsEmail = !campus.hasCampusAccess;
          campusDomain = campus.emailDomain;
          campusUnavailable = campus.hasCampusAccess && remote.isEmpty;
        }
      } else {
        // Near You — PostGIS expanding radii / hotspot.
        late final double lat;
        late final double lng;
        if (supabase.hasSessionLocation) {
          lat = supabase.sessionLatitude!;
          lng = supabase.sessionLongitude!;
        } else {
          final position = await LocationService.getCurrentPosition();
          if (isStale()) return;
          lat = position.latitude;
          lng = position.longitude;
          supabase.setSessionLocation(latitude: lat, longitude: lng);
        }

        final filter = _hotspotFilter;

        if (filter != null) {
          if (mounted && generation == _loadGeneration) {
            setState(() {
              _scanProgress = NearbyScanProgress.radius(
                radiusMeters:
                    filter.vicinityRadiusMeters ?? filter.radiusMeters,
              );
            });
          }
          // Hotspot kümesi — worldwide fallback yok; vicinity dışı izlenmez.
          remote = await supabase.fetchNearbyVideos(
            latitude: lat,
            longitude: lng,
            anchorLatitude: filter.latitude,
            anchorLongitude: filter.longitude,
            radiusMeters: filter.radiusMeters,
          );
          // Küme boşsa kullanıcının aktif halkasında, hotspot’a yakın taramayı dene.
          if (remote.isEmpty &&
              filter.vicinityRadiusMeters != null &&
              filter.vicinityRadiusMeters! > filter.radiusMeters) {
            remote = await supabase.fetchNearbyVideos(
              latitude: lat,
              longitude: lng,
              anchorLatitude: filter.latitude,
              anchorLongitude: filter.longitude,
              radiusMeters: math.min(
                filter.vicinityRadiusMeters!,
                filter.radiusMeters * 3,
              ),
            );
          }
        } else {
          final result = await supabase.fetchNearbyVideosExpanding(
            latitude: lat,
            longitude: lng,
            isCancelled: isStale,
            onProgress: (progress) {
              if (isStale()) return;
              setState(() => _scanProgress = progress);
            },
          );
          if (result.cancelled || isStale()) return;
          remote = result.posts;
          usedFallback = result.usedFallback;
        }

        if (isStale()) return;
      }

      if (isStale()) return;

      // Reload membership from DB so hearts survive cold start.
      Set<String> vibedFromServer = const {};
      if (remote.isNotEmpty && AuthService().isSignedIn) {
        vibedFromServer = await supabase.fetchMyVibedVideoIds(
          remote.map((p) => p.id),
        );
        if (isStale()) return;
      }

      // Son mesaj okunabilsin diye radar’ı hemen kapatma.
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (isStale()) return;

      setState(() {
        if (remote.isNotEmpty) {
          // Drop broken rows (empty URL) so the pager never sticks on black.
          final playable = remote
              .where((p) => p.videoUrl.trim().startsWith('http'))
              .toList(growable: true);
          _posts = playable;
          _currentIndex = 0;
          final loadedIds = playable.map((p) => p.id).toSet();
          _vibedIds.removeWhere(loadedIds.contains);
          _vibedIds.addAll(
            vibedFromServer.where(loadedIds.contains),
          );
        } else if (supabase.isReady) {
          _posts = <VibePost>[];
          _currentIndex = 0;
        }
        _scanProgress = null;
        _campusNeedsEmail = campusNeedsEmail;
        _campusDomain = campusDomain;
      });

      if (_posts.isNotEmpty && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      if (usedFallback && remote.isNotEmpty) {
        debugPrint(
          'VibeFeed: yakın boş → global/popüler fallback (${remote.length})',
        );
      }
      if (campusUnavailable &&
          tab == _tabCampus &&
          !_campusEmptyToasted &&
          mounted) {
        _campusEmptyToasted = true;
        _feedToast(context.s.campusTabEmpty);
      }
    } catch (e) {
      debugPrint('VibeFeed: uzak feed yüklenemedi. $e');
      if (!isStale()) {
        setState(() => _scanProgress = null);
      }
    } finally {
      // Stale yüklemeler nav/radar’ı kilitlemesin — yalnızca canlı generation.
      if (!isStale()) {
        _setRadarVisible(false);
      }
    }
  }

  void _setRadarVisible(bool visible) {
    if (_radarVisible == visible) return;
    setState(() => _radarVisible = visible);
    widget.onRadarVisibilityChanged?.call(visible);
  }

  @override
  void dispose() {
    // LayoutManager’daki radar bayrağını temizle (nav asla stuck kalmasın).
    if (_radarVisible) {
      widget.onRadarVisibilityChanged?.call(false);
    }
    _loadGeneration++;
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      // Only the active page may lock scroll; leave expansion behind.
      _infoExpanded = false;
    });
  }

  void _onInfoExpandedChanged(bool expanded) {
    if (_infoExpanded == expanded) return;
    setState(() => _infoExpanded = expanded);
  }

  Future<void> _toggleVibe(String id) async {
    final index = _posts.indexWhere((p) => p.id == id);
    if (index < 0) return;
    if (_vibeInFlight.contains(id)) return;

    if (SupabaseService.instance.isReady && !AuthService().isSignedIn) {
      if (!await _ensureSignedInForModeration()) return;
    }

    final wasVibed = _vibedIds.contains(id);
    final post = _posts[index];
    final optimisticCount =
        wasVibed ? (post.vibeCount - 1).clamp(0, 1 << 30) : post.vibeCount + 1;

    setState(() {
      if (wasVibed) {
        _vibedIds.remove(id);
      } else {
        _vibedIds.add(id);
      }
      _posts[index] = post.copyWith(vibeCount: optimisticCount);
    });

    if (!SupabaseService.instance.isReady || !AuthService().isSignedIn) {
      return;
    }

    _vibeInFlight.add(id);
    try {
      final result = await SupabaseService.instance.toggleVibe(id);
      if (!mounted) return;
      final latest = _posts.indexWhere((p) => p.id == id);
      if (latest < 0) return;
      setState(() {
        if (result.isVibed) {
          _vibedIds.add(id);
        } else {
          _vibedIds.remove(id);
        }
        _posts[latest] = _posts[latest].copyWith(vibeCount: result.vibeCount);
      });
    } catch (e) {
      debugPrint('VibeFeed._toggleVibe: $e');
      if (!mounted) return;
      final latest = _posts.indexWhere((p) => p.id == id);
      if (latest < 0) return;
      setState(() {
        if (wasVibed) {
          _vibedIds.add(id);
        } else {
          _vibedIds.remove(id);
        }
        _posts[latest] = _posts[latest].copyWith(vibeCount: post.vibeCount);
      });
    } finally {
      _vibeInFlight.remove(id);
    }
  }

  Future<void> _claimCampusEmail() async {
    if (!AuthService().isSignedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SignInScreen(),
        ),
      );
      if (!mounted || !AuthService().isSignedIn) return;
    }
    final profile = await showClaimStudentEmailSheet(context);
    if (!mounted) return;
    if (profile != null && profile.hasCampusAccess) {
      _feedToast(context.s.campusEmailLinkedToast);
      await _loadFeed();
    }
  }

  void _feedToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NoolColors.acid,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 110),
        content: Text(
          message,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: NoolColors.ink,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }

  Future<void> _sharePost(VibePost post) async {
    final s = AppStrings.fromSettings();
    final text = StringBuffer()
      ..writeln('${post.username} · Nool')
      ..writeln(
        post.caption.trim().isEmpty ? s.shareDefaultCaption : post.caption,
      )
      ..writeln(post.videoUrl);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text.toString().trim(),
          subject: 'Nool · ${post.username}',
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: post.videoUrl));
      _feedToast(s.linkCopied);
    }
  }

  Future<void> _copyPostLink(VibePost post) async {
    await Clipboard.setData(ClipboardData(text: post.videoUrl));
    _feedToast(AppStrings.fromSettings().linkCopied);
  }

  void _hidePost(String id, {required String toast}) {
    final removedIndex = _posts.indexWhere((p) => p.id == id);
    if (removedIndex < 0) return;

    setState(() {
      _posts = List<VibePost>.of(_posts)..removeAt(removedIndex);
      _vibedIds.remove(id);
      if (_posts.isEmpty) {
        _currentIndex = 0;
        return;
      }
      if (_currentIndex >= _posts.length) {
        _currentIndex = _posts.length - 1;
      } else if (removedIndex < _currentIndex) {
        _currentIndex -= 1;
      }
    });

    if (_posts.isNotEmpty && _pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pageController.hasClients) return;
        _pageController.jumpToPage(_currentIndex);
      });
    }

    _feedToast(toast);
  }

  void _hidePostsByUsername(String username, {required String toast}) {
    final target = SupabaseService.normalizeUsername(username);
    if (target == null) return;

    setState(() {
      final next = List<VibePost>.of(_posts);
      next.removeWhere((p) {
        final match = SupabaseService.normalizeUsername(p.username) == target;
        if (match) _vibedIds.remove(p.id);
        return match;
      });
      _posts = next;
      if (_posts.isEmpty) {
        _currentIndex = 0;
      } else if (_currentIndex >= _posts.length) {
        _currentIndex = _posts.length - 1;
      }
    });

    if (_posts.isNotEmpty && _pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pageController.hasClients) return;
        _pageController.jumpToPage(_currentIndex);
      });
    }

    _feedToast(toast);
  }

  Future<bool> _ensureSignedInForModeration() async {
    if (AuthService().isSignedIn) return true;
    final s = context.s;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NoolColors.night,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: NoolColors.acid, width: 3),
        ),
        title: Text(
          s.loginRequired,
          style: GoogleFonts.syne(
            color: NoolColors.acid,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          s.signInToModerate,
          style: GoogleFonts.syne(color: NoolColors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              s.cancel,
              style: GoogleFonts.syne(color: NoolColors.lavender),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.secureAccount,
              style: GoogleFonts.syne(
                color: NoolColors.acid,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      );
    }
    return AuthService().isSignedIn;
  }

  Future<void> _openReportFlow(VibePost post) async {
    final s = context.s;
    final action = await showModalBottomSheet<_ModerationAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ModerationEntrySheet(strings: s),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _ModerationAction.report:
        await _submitReport(post);
      case _ModerationAction.block:
        await _confirmAndBlock(post);
    }
  }

  Future<void> _submitReport(VibePost post) async {
    if (!await _ensureSignedInForModeration()) return;
    if (!mounted) return;

    final s = context.s;
    final reason = await showModalBottomSheet<_ReportReason>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ReportReasonSheet(strings: s),
    );
    if (!mounted || reason == null) return;

    try {
      if (SupabaseService.instance.isReady) {
        await SupabaseService.instance.reportVideo(
          videoId: post.id,
          reason: reason.apiValue,
        );
      }
      _hidePost(post.id, toast: s.reportReceived);
    } catch (e) {
      debugPrint('report failed: $e');
      // Still hide locally; never surface raw exception text to users.
      _hidePost(post.id, toast: s.reportReceived);
    }
  }

  Future<void> _confirmAndBlock(VibePost post) async {
    if (!await _ensureSignedInForModeration()) return;
    if (!mounted) return;

    final s = context.s;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NoolColors.night,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: NoolColors.tangerine, width: 3),
        ),
        title: Text(
          s.blockConfirmTitle,
          style: GoogleFonts.syne(
            color: NoolColors.tangerine,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          s.blockConfirmBody,
          style: GoogleFonts.syne(color: NoolColors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              s.cancel,
              style: GoogleFonts.syne(color: NoolColors.lavender),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.blockConfirmCta,
              style: GoogleFonts.syne(
                color: NoolColors.tangerine,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      if (SupabaseService.instance.isReady) {
        await SupabaseService.instance.blockUserByUsername(post.username);
      } else {
        final norm = SupabaseService.normalizeUsername(post.username);
        // Offline / demo: yerel gizle.
        if (norm != null) {
          // no-op beyond local remove
        }
      }
      _hidePostsByUsername(
        post.username,
        toast: s.userBlockedCampusClean,
      );
    } catch (e) {
      _hidePostsByUsername(
        post.username,
        toast: s.userBlockedCampusClean,
      );
      debugPrint('block failed: $e');
    }
  }

  Future<void> _openMoreMenu(VibePost post) async {
    final isOwn = _isOwnPost(post);
    final action = await showModalBottomSheet<_MoreAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MoreSheet(isOwnPost: isOwn),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _MoreAction.share:
        await _sharePost(post);
      case _MoreAction.copyLink:
        await _copyPostLink(post);
      case _MoreAction.notInterested:
        _hidePost(post.id, toast: context.s.notInterestedToast);
      case _MoreAction.delete:
        await _deleteOwnPost(post);
    }
  }

  Future<void> _deleteOwnPost(VibePost post) async {
    final s = context.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final d = AppStrings.of(ctx);
        return AlertDialog(
          backgroundColor: NoolColors.night,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NoolColors.acid, width: 3),
          ),
          title: Text(
            d.dropDeleteConfirmTitle,
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          content: Text(
            d.dropDeleteConfirmBody,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                d.cancel,
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Material(
              color: NoolColors.tangerine,
              child: InkWell(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: NoolColors.ink, width: 3),
                  ),
                  child: Text(
                    d.deleteConfirm,
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    try {
      // Extra ownership check (device_id) before destructive delete.
      final owned = await ProfileService().isOwnVideo(post);
      if (!owned) {
        if (!mounted) return;
        _feedToast(s.dropDeleteFailed);
        return;
      }
      await ProfileService().deleteMyVideo(post);
      if (!mounted) return;
      _hidePost(post.id, toast: s.dropDeletedToast);
    } catch (e) {
      if (!mounted) return;
      _feedToast('${s.dropDeleteFailed}: ${userFacingError(e, s)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Content clearance above floating nav (safe area added in _VibePage).
    // Nav 68 + margin 12 + ~8 gap → ~88. Eski 116 progress ile nav arasında
    // büyük siyah boşluk bırakıyordu.
    const bottomInset = 88.0;
    final tabs = [
      context.s.tabNearYou,
      context.s.tabVibing,
      context.s.tabCampus,
    ];

    Widget topChrome() {
      return Padding(
        padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TopBar(
              tabs: tabs,
              activeTab: _activeTab,
              onTabSelected: _onTabSelected,
              onReportCurrent: () {
                if (_posts.isEmpty) return;
                _openReportFlow(_posts[_currentIndex]);
              },
              onSearch: () {
                Navigator.of(context).push(PeopleSearchScreen.route());
              },
            ),
            if (_hotspotFilter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: clearHotspotFilter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: NoolColors.acid,
                        border: Border.all(
                          color: NoolColors.ink,
                          width: 2.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: NoolColors.ink,
                            offset: Offset(2, 2),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Text(
                        '${_hotspotFilter!.name}  ×',
                        style: const TextStyle(
                          color: NoolColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: NoolColors.night,
      // Gömülü feed: LayoutManager nav’ı sabit; klavye itmesin.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_posts.isEmpty && !_radarVisible)
            _activeTab == _tabCampus && _campusNeedsEmail
                ? _CampusEmailGate(
                    onClaim: _claimCampusEmail,
                    onSignIn: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SignInScreen(),
                        ),
                      );
                    },
                    signedIn: AuthService().isSignedIn,
                  )
                : _EmptyFeed(
                    onRefresh: () async {
                      if (_hotspotFilter != null) {
                        await clearHotspotFilter();
                      } else {
                        await _loadFeed();
                      }
                    },
                    message: _hotspotFilter != null
                        ? context.s.hotspotEmpty
                        : _activeTab == _tabCampus
                            ? context.s.campusTabEmpty
                            : context.s.emptyFeedHint,
                    domainLabel:
                        _activeTab == _tabCampus ? _campusDomain : null,
                  )
          else if (_posts.isNotEmpty)
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              physics: _infoExpanded
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              itemCount: _posts.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final post = _posts[index];
                final pageVisible = index == _currentIndex;
                return _VibePage(
                  key: ValueKey('${_activeTab}_${post.id}'),
                  post: post,
                  isActive: pageVisible,
                  isPlaybackEnabled:
                      widget.isFeedActive && pageVisible && !_radarVisible,
                  isVibed: _vibedIds.contains(post.id),
                  onVibe: () => _toggleVibe(post.id),
                  onShare: () => _sharePost(post),
                  onMore: () => _openMoreMenu(post),
                  onExpandedChanged:
                      pageVisible ? _onInfoExpandedChanged : null,
                  bottomContentInset: bottomInset,
                );
              },
            )
          else
            const ColoredBox(color: NoolColors.night),
          // Sekmeler her zaman erişilebilir (boş feed dahil); radar üstte örter.
          if (!_radarVisible) topChrome(),
          if (widget.showBottomNav)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomChrome(
                navIndex: _navIndex,
                onNavTap: (i) => setState(() => _navIndex = i),
              ),
            ),
          IgnorePointer(
            ignoring: !_radarVisible,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _radarVisible
                  ? NoolRadarOverlay(
                      key: const ValueKey('nool-radar'),
                      progress: _scanProgress,
                    )
                  : const SizedBox.shrink(key: ValueKey('nool-radar-off')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tam ekran Nool Radar — atmosfer + yavaş okunan durum metni.
class NoolRadarOverlay extends StatefulWidget {
  const NoolRadarOverlay({super.key, this.progress});

  final NearbyScanProgress? progress;

  @override
  State<NoolRadarOverlay> createState() => _NoolRadarOverlayState();
}

class _NoolRadarOverlayState extends State<NoolRadarOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _msgFade;
  late final AnimationController _radiusAnim;
  String _message = '';
  String? _pendingMessage;
  double _displayMeters = 0;
  double _fromMeters = 0;
  double _toMeters = 0;

  @override
  void initState() {
    super.initState();
    _msgFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: 1,
    );
    _radiusAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addListener(() {
        setState(() {
          _displayMeters =
              _fromMeters + (_toMeters - _fromMeters) * _radiusAnim.value;
        });
      });
    _message = widget.progress?.statusMessage ??
        AppStrings.fromSettings().radarScanning;
    final start = widget.progress?.radiusMeters ?? 500;
    _fromMeters = 0;
    _toMeters = start;
    _displayMeters = 0;
    _radiusAnim.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant NoolRadarOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.progress?.statusMessage ?? _message;
    if (next != _message && next != _pendingMessage) {
      _pendingMessage = next;
      _msgFade.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _message = next;
          _pendingMessage = null;
        });
        _msgFade.forward();
      });
    }

    final nextR = widget.progress?.radiusMeters;
    final wasFallback = oldWidget.progress?.isFallback ?? false;
    final isFallback = widget.progress?.isFallback ?? false;
    if (isFallback && !wasFallback) {
      _fromMeters = _displayMeters;
      _toMeters = _displayMeters;
      _radiusAnim.stop();
    } else if (nextR != null && nextR != _toMeters) {
      _fromMeters = _displayMeters > 0 ? _displayMeters : (_toMeters * 0.35);
      _toMeters = nextR;
      _radiusAnim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _msgFade.dispose();
    _radiusAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFallback = widget.progress?.isFallback ?? false;
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return SizedBox.expand(
      child: NoolAtmosphere(
        accent: isFallback ? AtmosphereAccent.tangerine : AtmosphereAccent.acid,
        intensity: 1.05,
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, topPad + 28, 28, bottomPad + 28),
          child: Column(
            children: [
              Text(
                'NOOL',
                style: GoogleFonts.syne(
                  color: NoolColors.acid,
                  fontWeight: FontWeight.w800,
                  fontSize: 42,
                  letterSpacing: -1.2,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'RADAR',
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 4,
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: 300,
                height: 300,
                child: isFallback
                    ? const NoolLottieView.fire(
                        width: 240,
                        height: 240,
                        energy: true,
                      )
                    : const NoolLottieView.radar(width: 280, height: 280),
              ),
              const Spacer(flex: 1),
              FadeTransition(
                opacity: _msgFade,
                child: NoolEmojiText(
                  _message,
                  textAlign: TextAlign.center,
                  emojiSize: 26,
                  style: GoogleFonts.syne(
                    color: NoolColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    height: 1.45,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (widget.progress != null && !isFallback) ...[
                const SizedBox(height: 14),
                Text(
                  _formatRadius(_displayMeters),
                  style: GoogleFonts.syne(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRadius(double meters) {
    if (meters < 1000) return '${meters.round()} m çap';
    return '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} km çap';
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.tabs,
    required this.activeTab,
    required this.onTabSelected,
    required this.onReportCurrent,
    required this.onSearch,
  });

  final List<String> tabs;
  final int activeTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onReportCurrent;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const NoolLogoMark(size: 28, border: true, shadow: false),
              const SizedBox(width: 8),
              Text(
                'NOOL',
                style: GoogleFonts.syne(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.6,
                  color: NoolColors.acid,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onSearch,
                tooltip: context.s.searchPeopleTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const NoolIcon(
                  NoolIconData.search,
                  color: NoolColors.acid,
                  size: 24,
                ),
              ),
              IconButton(
                onPressed: onReportCurrent,
                tooltip: context.s.reportTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const NoolIcon(
                  NoolIconData.flag,
                  color: NoolColors.white,
                  size: 22,
                ),
              ),
            ],
          ),
          // Sekmeler ayrı satır + FittedBox — bayrakla çakışma yok (üst Padding right: 16).
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < tabs.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          _TopTabChip(
                            label: tabs[i],
                            selected: i == activeTab,
                            onTap: () => onTabSelected(i),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopTabChip extends StatelessWidget {
  const _TopTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: GoogleFonts.syne(
                color: selected ? NoolColors.white : NoolColors.lavender,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: selected ? 28 : 0,
              color: NoolColors.acid,
            ),
          ],
        ),
      ),
    );
  }
}

class _VibePage extends StatefulWidget {
  const _VibePage({
    super.key,
    required this.post,
    required this.isActive,
    required this.isPlaybackEnabled,
    required this.isVibed,
    required this.onVibe,
    required this.onShare,
    required this.onMore,
    this.onExpandedChanged,
    this.bottomContentInset = 110,
  });

  final VibePost post;
  final bool isActive;
  final bool isPlaybackEnabled;
  final bool isVibed;
  final VoidCallback onVibe;
  final VoidCallback onShare;
  final VoidCallback onMore;

  /// Notifies parent so PageView can lock vertical scroll while expanded.
  final ValueChanged<bool>? onExpandedChanged;
  final double bottomContentInset;

  @override
  State<_VibePage> createState() => _VibePageState();
}

class _VibePageState extends State<_VibePage> {
  CachedVideoPlayerPlusController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _muted = !SettingsService.instance.feedSoundOn;
  bool _boosting = false;
  bool _scrubbing = false;
  bool _showMuteFlash = false;

  /// Reels-style caption / reaction panel (collapsed by default).
  bool _isExpanded = false;
  String? _selectedReaction;
  late Map<String, int> _reactionCounts;
  int _reactionEpoch = 0;

  void _setExpanded(bool value) {
    if (_isExpanded == value) return;
    setState(() => _isExpanded = value);
    widget.onExpandedChanged?.call(value);
  }

  @override
  void initState() {
    super.initState();
    _reactionCounts = Map<String, int>.from(widget.post.reactionCounts);
    if (widget.isActive) {
      _attach();
    }
    _loadMyReaction();
  }

  Future<void> _loadMyReaction() async {
    if (!SupabaseService.instance.isReady || !AuthService().isSignedIn) {
      return;
    }
    final mine =
        await SupabaseService.instance.fetchMyReactions(widget.post.id);
    if (!mounted) return;
    // Prefer a single selected chip (rail order).
    String? selected;
    for (final type in NoolReactionTypes.all) {
      if (mine.contains(type)) {
        selected = type;
        break;
      }
    }
    setState(() => _selectedReaction = selected);
  }

  Future<void> _onReact(String type) async {
    if (!SupabaseService.instance.isReady) return;

    if (!AuthService().isSignedIn) {
      final ok = await _ensureSignedInForReaction();
      if (!ok || !mounted) return;
    }

    final prev = _selectedReaction;
    final snapshot = Map<String, int>.from(_reactionCounts);
    final epoch = ++_reactionEpoch;

    // Optimistic single-select UI.
    setState(() {
      if (prev == type) {
        _selectedReaction = null;
        final next = (_reactionCounts[type] ?? 1) - 1;
        if (next <= 0) {
          _reactionCounts.remove(type);
        } else {
          _reactionCounts[type] = next;
        }
      } else {
        if (prev != null) {
          final next = (_reactionCounts[prev] ?? 1) - 1;
          if (next <= 0) {
            _reactionCounts.remove(prev);
          } else {
            _reactionCounts[prev] = next;
          }
        }
        _selectedReaction = type;
        _reactionCounts[type] = (_reactionCounts[type] ?? 0) + 1;
      }
    });

    try {
      final svc = SupabaseService.instance;
      // Switch: drop previous type first (toggle unvote), then vote new.
      if (prev != null && prev != type) {
        await svc.toggleReaction(videoId: widget.post.id, reactionType: prev);
      }
      final counts = await svc.toggleReaction(
        videoId: widget.post.id,
        reactionType: type,
      );
      if (!mounted || epoch != _reactionEpoch) return;
      setState(() {
        _reactionCounts = Map<String, int>.from(counts);
      });
    } catch (e) {
      debugPrint('VibePage._onReact: $e');
      if (!mounted || epoch != _reactionEpoch) return;
      setState(() {
        _selectedReaction = prev;
        _reactionCounts = snapshot;
      });
    }
  }

  Future<bool> _ensureSignedInForReaction() async {
    if (AuthService().isSignedIn) return true;
    final s = context.s;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NoolColors.night,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: NoolColors.acid, width: 3),
        ),
        title: Text(
          s.loginRequired,
          style: GoogleFonts.syne(
            color: NoolColors.acid,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          s.signInToModerate,
          style: GoogleFonts.syne(color: NoolColors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              s.cancel,
              style: GoogleFonts.syne(color: NoolColors.lavender),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.secureAccount,
              style: GoogleFonts.syne(
                color: NoolColors.acid,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      );
    }
    return AuthService().isSignedIn;
  }

  @override
  void didUpdateWidget(covariant _VibePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post.id != oldWidget.post.id) {
      _reactionCounts = Map<String, int>.from(widget.post.reactionCounts);
      _selectedReaction = null;
      if (_isExpanded) {
        _isExpanded = false;
        widget.onExpandedChanged?.call(false);
      }
      _loadMyReaction();
    } else if (widget.post.reactionCounts != oldWidget.post.reactionCounts &&
        _reactionEpoch == 0) {
      _reactionCounts = Map<String, int>.from(widget.post.reactionCounts);
    }
    if (widget.isActive && !oldWidget.isActive) {
      _attach();
    } else if (!widget.isActive && oldWidget.isActive) {
      if (_isExpanded) {
        _isExpanded = false;
        widget.onExpandedChanged?.call(false);
      }
      _detach();
    } else if (widget.isActive &&
        widget.isPlaybackEnabled != oldWidget.isPlaybackEnabled) {
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onVideoTick);
    controller?.dispose();
    super.dispose();
  }

  void _onVideoTick() {
    if (!_scrubbing && mounted) setState(() {});
  }

  Future<void> _attach() async {
    await _detach();
    if (!mounted) return;

    final rawUrl = widget.post.videoUrl.trim();
    final uri = Uri.tryParse(rawUrl);
    if (rawUrl.isEmpty ||
        uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      setState(() {
        _ready = false;
        _failed = true;
      });
      return;
    }

    Uri playableUri;
    try {
      playableUri =
          await SupabaseService.instance.playableVideoUri(uri.toString());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    final controller = CachedVideoPlayerPlusController.networkUrl(
      playableUri,
      invalidateCacheIfOlderThan: const Duration(days: 7),
    );

    _controller = controller;
    _ready = false;
    _failed = false;
    _boosting = false;
    setState(() {});

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      // Size must be valid before cover layout — avoids black “broken” frames.
      final sz = controller.value.size;
      if (sz.width <= 0 || sz.height <= 0) {
        throw StateError('video size unavailable');
      }
      await controller.setLooping(true);
      await controller.setPlaybackSpeed(1);
      await controller.setVolume(_muted ? 0 : 1);
      controller.addListener(_onVideoTick);
      if (widget.isPlaybackEnabled) {
        await controller.play();
      } else {
        await controller.pause();
      }
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
    } catch (_) {
      controller.removeListener(_onVideoTick);
      await controller.dispose();
      if (_controller == controller) {
        _controller = null;
      }
      if (mounted) {
        setState(() {
          _ready = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    try {
      if (widget.isPlaybackEnabled) {
        await controller.setVolume(_muted ? 0 : 1);
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {}
  }

  Future<void> _detach() async {
    final controller = _controller;
    _controller = null;
    _ready = false;
    _boosting = false;
    if (mounted) setState(() {});
    if (controller != null) {
      controller.removeListener(_onVideoTick);
      try {
        await controller.setPlaybackSpeed(1);
        await controller.pause();
      } catch (_) {}
      await controller.dispose();
    }
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final next = !_muted;
    setState(() {
      _muted = next;
      _showMuteFlash = true;
    });
    try {
      await controller.setVolume(next ? 0 : 1);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _showMuteFlash = false);
  }

  Future<void> _setBoost(bool on) async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    if (_boosting == on) return;
    setState(() => _boosting = on);
    try {
      await controller.setPlaybackSpeed(on ? 2 : 1);
    } catch (_) {}
  }

  Future<void> _seekFraction(double fraction) async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final duration = controller.value.duration;
    if (duration.inMilliseconds <= 0) return;
    final target = duration * fraction.clamp(0.0, 1.0);
    try {
      await controller.seekTo(target);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad =
        MediaQuery.viewPaddingOf(context).bottom + widget.bottomContentInset;
    final duration = _controller?.value.duration ?? Duration.zero;
    final position = _controller?.value.position ?? Duration.zero;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: NoolColors.night),
        if (_ready && _controller != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _isExpanded ? () => _setExpanded(false) : _toggleMute,
            onLongPressStart: _isExpanded ? null : (_) => _setBoost(true),
            onLongPressEnd: _isExpanded ? null : (_) => _setBoost(false),
            onLongPressCancel: _isExpanded ? null : () => _setBoost(false),
            child: AnimatedOpacity(
              opacity: _isExpanded ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: SizedBox.expand(
                child: NoolCoverVideo(controller: _controller!),
              ),
            ),
          )
        else
          Center(
            child: _failed
                ? const Icon(
                    Icons.videocam_off,
                    color: NoolColors.lavender,
                    size: 40,
                  )
                : const NoolLottieView.loading(
                    width: 56,
                    height: 56,
                    compact: true,
                  ),
          ),
        // Dim overlay while info card expanded (tap video already collapses).
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setExpanded(false),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
              ),
            ),
          ),
        // Alt gradient — metin okunabilirliği
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 280,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    NoolColors.night.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showMuteFlash || _boosting)
          Center(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: (_showMuteFlash || _boosting) ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: NoolColors.night.withValues(alpha: 0.72),
                    border: Border.all(color: NoolColors.ink, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: NoolColors.ink,
                        offset: Offset(3, 3),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Text(
                    _boosting
                        ? '2×'
                        : (_muted ? context.s.muted : context.s.soundOn),
                    style: const TextStyle(
                      color: NoolColors.acid,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Seek strip sits below caption / actions so "...devamı" isn't stolen.
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomPad,
          child: _VideoSeekBar(
            progress: progress,
            onSeekStart: () => setState(() => _scrubbing = true),
            onSeekUpdate: _seekFraction,
            onSeekEnd: (fraction) async {
              await _seekFraction(fraction);
              if (mounted) setState(() => _scrubbing = false);
            },
          ),
        ),
        // Sol alt — Reels tarzı collapsible bilgi kartı (above seek, higher z)
        Positioned(
          left: 14,
          right: 84,
          bottom: bottomPad + _VideoSeekBar.hitHeight + 10,
          child: _InfoCard(
            post: widget.post,
            isExpanded: _isExpanded,
            onExpand: () => _setExpanded(true),
            onCollapse: () => _setExpanded(false),
            reactionBar: NoolReactionBar(
              selected: _selectedReaction,
              counts: _reactionCounts,
              onReact: _onReact,
            ),
          ),
        ),
        // Sağ aksiyonlar — soft glass circles
        Positioned(
          right: 10,
          bottom: bottomPad + _VideoSeekBar.hitHeight + 10,
          child: _ActionRail(
            isVibed: widget.isVibed,
            vibeLabel: widget.post.vibeCountLabel,
            commentLabel: widget.post.commentCountLabel,
            onVibe: widget.onVibe,
            onComment: () => showCommentsSheet(
              context,
              videoId: widget.post.id,
            ),
            onShare: widget.onShare,
            onMore: widget.onMore,
          ),
        ),
      ],
    );
  }
}

class _VideoSeekBar extends StatefulWidget {
  const _VideoSeekBar({
    required this.progress,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
  });

  /// Opaque vertical hit strip — keep caption / "...devamı" above this.
  static const double hitHeight = 20;

  final double progress;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;

  @override
  State<_VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<_VideoSeekBar> {
  double? _dragProgress;

  double _fractionFor(Offset local, double width) {
    if (width <= 0) return 0;
    return (local.dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final shown = (_dragProgress ?? widget.progress).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            widget.onSeekStart();
            final t = _fractionFor(details.localPosition, width);
            setState(() => _dragProgress = t);
            widget.onSeekUpdate(t);
          },
          onHorizontalDragUpdate: (details) {
            final t = _fractionFor(details.localPosition, width);
            setState(() => _dragProgress = t);
            widget.onSeekUpdate(t);
          },
          onHorizontalDragEnd: (_) {
            final t = _dragProgress ?? widget.progress;
            widget.onSeekEnd(t);
            setState(() => _dragProgress = null);
          },
          onTapDown: (details) {
            widget.onSeekStart();
            final t = _fractionFor(details.localPosition, width);
            setState(() => _dragProgress = t);
            widget.onSeekUpdate(t);
            widget.onSeekEnd(t);
            setState(() => _dragProgress = null);
          },
          child: SizedBox(
            height: _VideoSeekBar.hitHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 10,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 3,
                      width: double.infinity,
                      color: Colors.white24,
                    ),
                    FractionallySizedBox(
                      widthFactor: shown,
                      child: Container(
                        height: 3,
                        color: NoolColors.acid,
                      ),
                    ),
                    Positioned(
                      left: (width - 10) * shown,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: NoolColors.acid,
                          shape: BoxShape.circle,
                          border: Border.all(color: NoolColors.ink, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.post,
    required this.isExpanded,
    required this.onExpand,
    required this.onCollapse,
    this.reactionBar,
  });

  final VibePost post;
  final bool isExpanded;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final Widget? reactionBar;

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -220) {
          onExpand();
        } else if (v > 220) {
          onCollapse();
        }
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: Alignment.bottomLeft,
        child: isExpanded
            ? _ExpandedInfoPanel(
                post: post,
                reactionBar: reactionBar,
                onCollapse: onCollapse,
                seeLessLabel: s.seeLess,
              )
            : _CollapsedInfoLine(
                post: post,
                seeMoreLabel: s.seeMore,
                onExpand: onExpand,
              ),
      ),
    );
  }
}

class _CollapsedInfoLine extends StatelessWidget {
  const _CollapsedInfoLine({
    required this.post,
    required this.seeMoreLabel,
    required this.onExpand,
  });

  final VibePost post;
  final String seeMoreLabel;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: post.username,
                  style: GoogleFonts.syne(
                    color: NoolColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                TextSpan(
                  text: ' • ',
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                TextSpan(
                  text: post.caption.trim(),
                  style: GoogleFonts.syne(
                    color: NoolColors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onExpand,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  seeMoreLabel,
                  style: GoogleFonts.syne(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    shadows: [
                      Shadow(
                        color: NoolColors.acid.withValues(alpha: 0.85),
                        blurRadius: 10,
                      ),
                      Shadow(
                        color: NoolColors.acid.withValues(alpha: 0.45),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandedInfoPanel extends StatelessWidget {
  const _ExpandedInfoPanel({
    required this.post,
    required this.onCollapse,
    required this.seeLessLabel,
    this.reactionBar,
  });

  final VibePost post;
  final VoidCallback onCollapse;
  final String seeLessLabel;
  final Widget? reactionBar;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0x800D0A1C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thin drag handle + see less
              GestureDetector(
                onTap: onCollapse,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: NoolColors.lavender.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        seeLessLabel,
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Acid distance badge — Inter so 0 ≠ o
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: NoolColors.acid,
                  border: Border.all(color: NoolColors.ink, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: NoolColors.ink,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  '• ${post.distanceLabel}',
                  style: _noolMetaLabelStyle(
                    color: NoolColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (reactionBar != null) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: reactionBar!,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        OtherProfileScreen.route(username: post.username),
                      );
                    },
                    child: NoolAvatar(
                      size: 32,
                      borderWidth: 2,
                      imageUrl: post.avatarUrl,
                      fallbackInitial: post.username,
                      backgroundColor: post.avatarColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          OtherProfileScreen.route(username: post.username),
                        );
                      },
                      child: Text(
                        post.username,
                        style: GoogleFonts.syne(
                          color: NoolColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.caption,
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.isVibed,
    required this.vibeLabel,
    required this.commentLabel,
    required this.onVibe,
    required this.onComment,
    required this.onShare,
    required this.onMore,
  });

  final bool isVibed;
  final String vibeLabel;
  final String commentLabel;
  final VoidCallback onVibe;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VibeButton(
          isVibed: isVibed,
          label: vibeLabel,
          onTap: onVibe,
        ),
        const SizedBox(height: 18),
        _CircleAction(
          icon: NoolIconData.comment,
          label: commentLabel,
          onTap: onComment,
        ),
        const SizedBox(height: 18),
        _CircleAction(
          icon: NoolIconData.send,
          label: s.share,
          onTap: onShare,
        ),
        const SizedBox(height: 18),
        _CircleAction(
          icon: NoolIconData.more,
          label: s.more,
          onTap: onMore,
        ),
      ],
    );
  }
}

enum _MoreAction { share, copyLink, notInterested, delete }

enum _ModerationAction { report, block }

enum _ReportReason {
  spam('spam'),
  harassment('harassment'),
  sexual('sexual'),
  violence('violence'),
  misinfo('misinfo'),
  other('other');

  const _ReportReason(this.apiValue);
  final String apiValue;

  String labelFor(AppStrings s) {
    switch (this) {
      case _ReportReason.spam:
        return s.reportSpam;
      case _ReportReason.harassment:
        return s.reportHarassment;
      case _ReportReason.sexual:
        return s.reportSexual;
      case _ReportReason.violence:
        return s.reportViolence;
      case _ReportReason.misinfo:
        return s.reportMisinfo;
      case _ReportReason.other:
        return s.reportOther;
    }
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({this.isOwnPost = false});

  final bool isOwnPost;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Container(
        decoration: BoxDecoration(
          color: NoolColors.night,
          border: Border.all(color: NoolColors.ink, width: 3),
          boxShadow: const [
            BoxShadow(
              color: NoolColors.ink,
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                color: NoolColors.lavender,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.options,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.ios_share_rounded,
                label: s.share,
                onTap: () => Navigator.pop(context, _MoreAction.share),
              ),
              _MoreTile(
                icon: Icons.link_rounded,
                label: s.copyLink,
                onTap: () => Navigator.pop(context, _MoreAction.copyLink),
              ),
              if (isOwnPost)
                _MoreTile(
                  icon: Icons.delete_outline_rounded,
                  label: s.dropDelete,
                  destructive: true,
                  onTap: () => Navigator.pop(context, _MoreAction.delete),
                ),
              _MoreTile(
                icon: Icons.visibility_off_outlined,
                label: s.notInterested,
                onTap: () => Navigator.pop(context, _MoreAction.notInterested),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModerationEntrySheet extends StatelessWidget {
  const _ModerationEntrySheet({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Container(
        decoration: BoxDecoration(
          color: NoolColors.night,
          border: Border.all(color: NoolColors.ink, width: 3),
          boxShadow: const [
            BoxShadow(
              color: NoolColors.ink,
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  color: NoolColors.lavender,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  strings.moderationTitle,
                  style: GoogleFonts.syne(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  strings.reportHelp,
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _MoreTile(
                icon: Icons.flag_outlined,
                label: strings.reportThisVideo,
                onTap: () => Navigator.pop(context, _ModerationAction.report),
              ),
              _MoreTile(
                icon: Icons.block,
                label: strings.blockThisUser,
                destructive: true,
                onTap: () => Navigator.pop(context, _ModerationAction.block),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportReasonSheet extends StatelessWidget {
  const _ReportReasonSheet({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Container(
        decoration: BoxDecoration(
          color: NoolColors.night,
          border: Border.all(color: NoolColors.ink, width: 3),
          boxShadow: const [
            BoxShadow(
              color: NoolColors.ink,
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  color: NoolColors.lavender,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  strings.reportWhy,
                  style: GoogleFonts.syne(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  strings.reportHelp,
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final reason in _ReportReason.values)
                _MoreTile(
                  icon: Icons.flag_outlined,
                  label: reason.labelFor(strings),
                  destructive: reason == _ReportReason.violence ||
                      reason == _ReportReason.sexual,
                  onTap: () => Navigator.pop(context, reason),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? NoolColors.tangerine : NoolColors.white;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
      onTap: onTap,
    );
  }
}

class _VibeButton extends StatefulWidget {
  const _VibeButton({
    required this.isVibed,
    required this.label,
    required this.onTap,
  });

  final bool isVibed;
  final String label;
  final VoidCallback onTap;

  @override
  State<_VibeButton> createState() => _VibeButtonState();
}

class _VibeButtonState extends State<_VibeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.22), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.22, end: 1), weight: 55),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant _VibeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVibed != oldWidget.isVibed) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isVibed ? NoolColors.tangerine : NoolColors.white;
    return Column(
      children: [
        ScaleTransition(
          scale: _scale,
          child: GestureDetector(
            onTap: () {
              if (SettingsService.instance.hapticsOn) {
                HapticFeedback.selectionClick();
              }
              widget.onTap();
            },
            child: _GlassCircle(
              child: NoolIcon(
                widget.isVibed ? NoolIconData.heart : NoolIconData.heartOutline,
                color: iconColor,
                size: 26,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.label,
          style: _noolMetaLabelStyle(),
        ),
      ],
    );
  }
}

/// Soft glass circular action chrome (feed right rail).
class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0x800D0A1C),
            shape: BoxShape.circle,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Inter for numeric / meta rail labels — keeps digit 0 distinct from letter o.
TextStyle _noolMetaLabelStyle({
  Color color = NoolColors.white,
  double fontSize = 11,
  FontWeight fontWeight = FontWeight.w700,
}) {
  return GoogleFonts.inter(
    color: color,
    fontWeight: fontWeight,
    fontSize: fontSize,
    letterSpacing: 0.35,
    height: 1.15,
    fontFeatures: const [
      FontFeature.tabularFigures(),
      FontFeature.liningFigures(),
    ],
  );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final NoolIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: _GlassCircle(
            child: NoolIcon(icon, color: NoolColors.white, size: 24),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            label,
            style: _noolMetaLabelStyle(),
          ),
        ],
      ],
    );
  }
}

class _BottomChrome extends StatelessWidget {
  const _BottomChrome({
    required this.navIndex,
    required this.onNavTap,
  });

  final int navIndex;
  final ValueChanged<int> onNavTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: NoolColors.ink,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 10, 8, 10 + bottom),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: NoolIconData.homeOutline,
              activeIcon: NoolIconData.home,
              label: s.navFeed,
              active: navIndex == 0,
              onTap: () => onNavTap(0),
            ),
            _NavItem(
              icon: NoolIconData.cameraOutline,
              activeIcon: NoolIconData.camera,
              label: s.navCamera,
              active: navIndex == 1,
              onTap: () => onNavTap(1),
            ),
            GestureDetector(
              onTap: () => onNavTap(2),
              child: Container(
                width: 48,
                height: 40,
                decoration: BoxDecoration(
                  color: NoolColors.acid,
                  border: Border.all(color: NoolColors.ink, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: NoolColors.ink,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: const Center(
                  child: NoolIcon(
                    NoolIconData.add,
                    color: NoolColors.ink,
                    size: 26,
                  ),
                ),
              ),
            ),
            _NavItem(
              icon: NoolIconData.send,
              label: s.navMessages,
              active: navIndex == 3,
              onTap: () => onNavTap(3),
            ),
            _NavItem(
              icon: NoolIconData.personOutline,
              activeIcon: NoolIconData.person,
              label: s.navProfile,
              active: navIndex == 4,
              onTap: () => onNavTap(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeIcon,
  });

  final NoolIconData icon;
  final NoolIconData? activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? NoolColors.acid : NoolColors.lavender;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NoolIcon(
              active ? (activeIcon ?? icon) : icon,
              color: color,
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampusEmailGate extends StatelessWidget {
  const _CampusEmailGate({
    required this.onClaim,
    required this.onSignIn,
    required this.signedIn,
  });

  final VoidCallback onClaim;
  final VoidCallback onSignIn;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nool',
              style: GoogleFonts.syne(
                color: NoolColors.acid,
                fontWeight: FontWeight.w800,
                fontSize: 36,
                height: 1,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              s.campusNeedEmailTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.campusNeedEmailBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Material(
                color: NoolColors.acid,
                child: InkWell(
                  onTap: signedIn ? onClaim : onSignIn,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: NoolColors.ink, width: 3.5),
                    ),
                    child: Text(
                      signedIn ? s.campusClaimCta : s.campusUnlockSignIn,
                      style: GoogleFonts.syne(
                        color: NoolColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({
    required this.onRefresh,
    this.message,
    this.domainLabel,
  });

  final Future<void> Function() onRefresh;
  final String? message;
  final String? domainLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Akış boş.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (domainLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                '@$domainLabel',
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              message ?? context.s.reportHiddenRefresh,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: NoolColors.lavender,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => onRefresh(),
              child: Text(context.s.retry),
            ),
          ],
        ),
      ),
    );
  }
}
