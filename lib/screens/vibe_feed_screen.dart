import 'dart:ui';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/campus_hotspot.dart';
import '../models/vibe_post.dart';
import '../icons/nool_emojis.dart';
import '../icons/nool_icons.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'other_profile_screen.dart';

/// TikTok tarzı dikey vibe video akışı.
class VibeFeedScreen extends StatefulWidget {
  const VibeFeedScreen({
    super.key,
    this.username,
    this.isFeedActive = true,
    this.showBottomNav = true,
  });

  final String? username;

  /// LayoutManager kamera/trend sekmesindeyken false — videolar pause.
  final bool isFeedActive;

  /// LayoutManager kendi nav’ını gösteriyorsa false.
  final bool showBottomNav;

  @override
  State<VibeFeedScreen> createState() => VibeFeedScreenState();
}

class VibeFeedScreenState extends State<VibeFeedScreen> {
  static const _tabs = ['Near You', 'Vibing', 'Campus'];

  late final PageController _pageController;
  late List<VibePost> _posts;

  int _currentIndex = 0;
  int _activeTab = 1;
  int _navIndex = 1;
  final Set<String> _vibedIds = {};
  HotspotFeedFilter? _hotspotFilter;

  /// Artan id — eski async yüklemeleri yok saymak için.
  int _loadGeneration = 0;
  bool _radarVisible = false;
  NearbyScanProgress? _scanProgress;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _posts = List<VibePost>.from(_demoPosts);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: NoolColors.ink,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _loadFeed();
  }

  Future<void> reloadFeed() => _loadFeed();

  /// Trend ekranından gelen konum filtresi.
  Future<void> applyHotspotFilter(CampusHotspot hotspot) async {
    setState(() {
      _hotspotFilter = HotspotFeedFilter(
        latitude: hotspot.latitude,
        longitude: hotspot.longitude,
        name: hotspot.name,
      );
      _activeTab = 0;
    });
    await _loadFeed();
  }

  Future<void> clearHotspotFilter() async {
    setState(() => _hotspotFilter = null);
    await _loadFeed();
  }

  Future<void> _loadFeed() async {
    final supabase = SupabaseService.instance;
    if (!supabase.isReady) return;

    final generation = ++_loadGeneration;
    bool isStale() => !mounted || generation != _loadGeneration;

    setState(() {
      _radarVisible = true;
      _scanProgress = NearbyScanProgress.radius(radiusMeters: 500);
    });

    try {
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
      late final List<VibePost> remote;
      var usedFallback = false;

      if (filter != null) {
        // Hotspot: sabit yarıçap — genişletme yok.
        if (mounted && generation == _loadGeneration) {
          setState(() {
            _scanProgress = NearbyScanProgress.radius(
              radiusMeters: filter.radiusMeters,
            );
          });
        }
        remote = await supabase.fetchNearbyVideos(
          latitude: lat,
          longitude: lng,
          anchorLatitude: filter.latitude,
          anchorLongitude: filter.longitude,
          radiusMeters: filter.radiusMeters,
        );
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

      if (remote.isEmpty && filter == null && !usedFallback) {
        // Genişletme + fallback boş — demo kalsın, radar kapansın.
        setState(() {
          _radarVisible = false;
          _scanProgress = null;
        });
        return;
      }

      setState(() {
        if (remote.isEmpty && filter != null) {
          _posts = const [];
        } else if (remote.isNotEmpty) {
          _posts = remote;
          _currentIndex = 0;
        }
        _radarVisible = false;
        _scanProgress = null;
      });
      if (_posts.isNotEmpty && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } catch (e) {
      debugPrint('VibeFeed: uzak feed yüklenemedi — demo devam. $e');
      if (!isStale()) {
        setState(() {
          _radarVisible = false;
          _scanProgress = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _toggleVibe(String id) {
    setState(() {
      if (_vibedIds.contains(id)) {
        _vibedIds.remove(id);
      } else {
        _vibedIds.add(id);
      }
    });
  }

  void _reportPost(String id) {
    final removedIndex = _posts.indexWhere((p) => p.id == id);
    if (removedIndex < 0) return;

    setState(() {
      _posts.removeAt(removedIndex);
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NoolColors.acid,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Şikayet alındı — video gizlendi.',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: NoolColors.ink,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = widget.showBottomNav
        ? 0.0
        : MediaQuery.paddingOf(context).bottom + 88;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_posts.isEmpty && !_radarVisible)
            _EmptyFeed(
              onRefresh: () async {
                if (_hotspotFilter != null) {
                  await clearHotspotFilter();
                } else {
                  setState(() {
                    _posts = List<VibePost>.from(_demoPosts);
                    _currentIndex = 0;
                  });
                  await _loadFeed();
                }
              },
              message: _hotspotFilter == null
                  ? null
                  : 'Bu noktada henüz drop yok.\nFiltreyi kaldırıp tüm kampüse dön.',
            )
          else if (_posts.isNotEmpty)
            Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _posts.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final post = _posts[index];
                    final pageVisible = index == _currentIndex;
                    return _VibePage(
                      key: ValueKey(post.id),
                      post: post,
                      isActive: pageVisible,
                      isPlaybackEnabled:
                          widget.isFeedActive && pageVisible && !_radarVisible,
                      isVibed: _vibedIds.contains(post.id),
                      onVibe: () => _toggleVibe(post.id),
                      onReport: () => _reportPost(post.id),
                      bottomContentInset: bottomInset,
                    );
                  },
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TopBar(
                        tabs: _tabs,
                        activeTab: _activeTab,
                        onTabSelected: (i) => setState(() => _activeTab = i),
                        onReportCurrent: () {
                          if (_posts.isEmpty) return;
                          _reportPost(_posts[_currentIndex].id);
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
                ),
                if (widget.showBottomNav)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _BottomChrome(
                      navIndex: _navIndex,
                      onNavTap: (i) => setState(() => _navIndex = i),
                      progress: _posts.isEmpty
                          ? 0
                          : (_currentIndex + 1) / _posts.length,
                    ),
                  )
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset,
                    child: LinearProgressIndicator(
                      value: (_currentIndex + 1) / _posts.length,
                      minHeight: 2.5,
                      backgroundColor: Colors.white12,
                      color: NoolColors.acid,
                    ),
                  ),
              ],
            )
          else
            const ColoredBox(color: NoolColors.night),
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

/// Asit yeşili Nool Radar — Lottie + Gen-Z durum mesajı.
class NoolRadarOverlay extends StatefulWidget {
  const NoolRadarOverlay({super.key, this.progress});

  final NearbyScanProgress? progress;

  @override
  State<NoolRadarOverlay> createState() => _NoolRadarOverlayState();
}

class _NoolRadarOverlayState extends State<NoolRadarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _msgFade;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _msgFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    _message = widget.progress?.statusMessage ?? 'Nool Radar taranıyor...';
  }

  @override
  void didUpdateWidget(covariant NoolRadarOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.progress?.statusMessage ?? _message;
    if (next != _message) {
      _msgFade.reverse().then((_) {
        if (!mounted) return;
        setState(() => _message = next);
        _msgFade.forward();
      });
    }
  }

  @override
  void dispose() {
    _msgFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFallback = widget.progress?.isFallback ?? false;

    return ColoredBox(
      color: NoolColors.night,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 36),
            Text(
              'NOOL RADAR',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
            ),
            const Spacer(flex: 2),
            SizedBox(
              width: 260,
              height: 260,
              child: isFallback
                  ? const NoolLottieView.fire(width: 200, height: 200, energy: true)
                  : const NoolLottieView.radar(width: 240, height: 240),
            ),
            const Spacer(flex: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FadeTransition(
                opacity: _msgFade,
                child: NoolEmojiText(
                  _message,
                  textAlign: TextAlign.center,
                  emojiSize: 22,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: NoolColors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                ),
              ),
            ),
            if (widget.progress != null && !widget.progress!.isFallback) ...[
              const SizedBox(height: 10),
              Text(
                _formatRadius(widget.progress!.radiusMeters),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  String _formatRadius(double? meters) {
    if (meters == null) return '';
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
  });

  final List<String> tabs;
  final int activeTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onReportCurrent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          const NoolLogoMark(size: 32, border: true, shadow: false),
          const SizedBox(width: 10),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return const LinearGradient(
                colors: [NoolColors.lavender, NoolColors.acid],
              ).createShader(bounds);
            },
            child: Text(
              'NOOL',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    letterSpacing: -0.8,
                    color: Colors.white,
                  ),
            ),
          ),
          const Spacer(),
          for (var i = 0; i < tabs.length; i++) ...[
            GestureDetector(
              onTap: () => onTabSelected(i),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tabs[i],
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: i == activeTab
                                ? NoolColors.white
                                : NoolColors.lavender,
                            fontWeight:
                                i == activeTab ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 13,
                          ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 3,
                      width: i == activeTab ? 28 : 0,
                      color: NoolColors.acid,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            onPressed: onReportCurrent,
            tooltip: 'Rapor et',
            icon: const NoolIcon(
              NoolIconData.flag,
              color: NoolColors.white,
              size: 22,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const NoolIcon(
              NoolIconData.search,
              color: NoolColors.white,
              size: 24,
            ),
          ),
        ],
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
    required this.onReport,
    this.bottomContentInset = 88,
  });

  final VibePost post;
  final bool isActive;
  final bool isPlaybackEnabled;
  final bool isVibed;
  final VoidCallback onVibe;
  final VoidCallback onReport;
  final double bottomContentInset;

  @override
  State<_VibePage> createState() => _VibePageState();
}

class _VibePageState extends State<_VibePage> {
  CachedVideoPlayerPlusController? _controller;
  bool _ready = false;
  bool _failed = false;
  NoolEmojiData? _selectedReaction;
  final Map<NoolEmojiData, int> _reactionCounts = {
    NoolEmojiData.cool: 12,
    NoolEmojiData.fire: 8,
    NoolEmojiData.laugh: 3,
    NoolEmojiData.dead: 1,
    NoolEmojiData.party: 5,
  };

  void _onReact(NoolEmojiData emoji) {
    setState(() {
      if (_selectedReaction == emoji) {
        _reactionCounts[emoji] = (_reactionCounts[emoji] ?? 1) - 1;
        if ((_reactionCounts[emoji] ?? 0) <= 0) {
          _reactionCounts.remove(emoji);
        }
        _selectedReaction = null;
      } else {
        if (_selectedReaction != null) {
          final prev = _selectedReaction!;
          _reactionCounts[prev] = (_reactionCounts[prev] ?? 1) - 1;
          if ((_reactionCounts[prev] ?? 0) <= 0) {
            _reactionCounts.remove(prev);
          }
        }
        _selectedReaction = emoji;
        _reactionCounts[emoji] = (_reactionCounts[emoji] ?? 0) + 1;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _attach();
    }
  }

  @override
  void didUpdateWidget(covariant _VibePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _attach();
    } else if (!widget.isActive && oldWidget.isActive) {
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
    controller?.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    await _detach();
    if (!mounted) return;

    final controller = CachedVideoPlayerPlusController.networkUrl(
      Uri.parse(widget.post.videoUrl),
      invalidateCacheIfOlderThan: const Duration(days: 7),
    );

    _controller = controller;
    _ready = false;
    _failed = false;
    setState(() {});

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (widget.isPlaybackEnabled) {
        await controller.play();
      } else {
        await controller.pause();
      }
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
    } catch (_) {
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
    if (mounted) setState(() {});
    if (controller != null) {
      try {
        await controller.pause();
      } catch (_) {}
      await controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad =
        MediaQuery.paddingOf(context).bottom + widget.bottomContentInset;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: NoolColors.night),
        if (_ready && _controller != null)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: CachedVideoPlayerPlus(_controller!),
            ),
          )
        else
          Center(
            child: _failed
                ? const Icon(Icons.videocam_off, color: NoolColors.lavender, size: 40)
                : const NoolLottieView.loading(
                    width: 56,
                    height: 56,
                    compact: true,
                  ),
          ),
        // Alt gradient — metin okunabilirliği
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  NoolColors.night.withOpacity(0.75),
                ],
              ),
            ),
          ),
        ),
        // Sağ üst rapor (sayfa içi — BTK)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 56,
          right: 12,
          child: _ReportChip(onTap: widget.onReport),
        ),
        // Sol alt bilgi kartı + neo-brutal emoji reactions
        Positioned(
          left: 14,
          right: 84,
          bottom: bottomPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              NoolReactionBar(
                selected: _selectedReaction,
                counts: _reactionCounts,
                onReact: _onReact,
              ),
              const SizedBox(height: 10),
              _InfoCard(post: widget.post),
            ],
          ),
        ),
        // Sağ aksiyonlar
        Positioned(
          right: 10,
          bottom: bottomPad + 8,
          child: _ActionRail(
            isVibed: widget.isVibed,
            vibeLabel: widget.post.vibeCountLabel,
            commentLabel: widget.post.commentCountLabel,
            onVibe: widget.onVibe,
                      onComment: () => showCommentsSheet(
                        context,
                        videoId: widget.post.id,
                      ),
            onShare: () {},
          ),
        ),
      ],
    );
  }
}

class _ReportChip extends StatelessWidget {
  const _ReportChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.45),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white24, width: 1.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.flag, color: NoolColors.white, size: 18),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.post});

  final VibePost post;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.42),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Neo-brutalist mesafe rozeti
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: NoolColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        OtherProfileScreen.route(username: post.username),
                      );
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: post.avatarColor,
                      child: Text(
                        post.username
                            .replaceFirst('@', '')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          color: NoolColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              OtherProfileScreen.route(
                                username: post.username,
                              ),
                            );
                          },
                          child: Text(
                            post.username,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: NoolColors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                          ),
                        ),
                        Text(
                          post.subtitle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: NoolColors.lavender,
                                    fontSize: 12,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.caption,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NoolColors.white,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const NoolIcon(
                    NoolIconData.music,
                    size: 14,
                    color: NoolColors.lavender,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      post.trackLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NoolColors.lavender,
                            fontSize: 12,
                          ),
                    ),
                  ),
                ],
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
  });

  final bool isVibed;
  final String vibeLabel;
  final String commentLabel;
  final VoidCallback onVibe;
  final VoidCallback onComment;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
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
          label: 'Share',
          onTap: onShare,
        ),
        const SizedBox(height: 18),
        _CircleAction(
          icon: NoolIconData.more,
          label: '',
          onTap: () {},
        ),
      ],
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
      duration: const Duration(milliseconds: 280),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void didUpdateWidget(covariant _VibeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVibed && !oldWidget.isVibed) {
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
    final color = widget.isVibed ? NoolColors.tangerine : NoolColors.white;

    return Column(
      children: [
        ScaleTransition(
          scale: _scale,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onTap: widget.onTap,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.35),
                      border: Border.all(
                        color: widget.isVibed
                            ? NoolColors.tangerine.withOpacity(0.9)
                            : Colors.white24,
                        width: 1.5,
                      ),
                      boxShadow: widget.isVibed
                          ? [
                              BoxShadow(
                                color: NoolColors.tangerine.withOpacity(0.55),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: NoolIcon(
                        widget.isVibed
                            ? NoolIconData.heart
                            : NoolIconData.heartOutline,
                        color: color,
                        size: 26,
                      ),
                    ),
                  ),
                ),
                if (widget.isVibed)
                  const Positioned(
                    right: -8,
                    top: -12,
                    child: IgnorePointer(
                      child: NoolLottieView.fire(
                        width: 40,
                        height: 40,
                        energy: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: NoolColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
        ),
      ],
    );
  }
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
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.35),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Center(
              child: NoolIcon(icon, color: NoolColors.white, size: 24),
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
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
    required this.progress,
  });

  final int navIndex;
  final ValueChanged<int> onNavTap;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: LinearProgressIndicator(
            value: progress.clamp(0.05, 1),
            minHeight: 2.5,
            backgroundColor: Colors.white12,
            color: NoolColors.acid,
          ),
        ),
        ColoredBox(
          color: NoolColors.ink,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 10, 8, 10 + bottom),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: NoolIconData.homeOutline,
                  activeIcon: NoolIconData.home,
                  label: 'Home',
                  active: navIndex == 0,
                  onTap: () => onNavTap(0),
                ),
                _NavItem(
                  icon: NoolIconData.fireOutline,
                  activeIcon: NoolIconData.fire,
                  label: 'Near',
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
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NoolColors.ink, width: 2.5),
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
                  icon: NoolIconData.more,
                  label: 'Notifs',
                  active: navIndex == 3,
                  onTap: () => onNavTap(3),
                ),
                _NavItem(
                  icon: NoolIconData.personOutline,
                  activeIcon: NoolIconData.person,
                  label: 'Me',
                  active: navIndex == 4,
                  onTap: () => onNavTap(4),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.onRefresh, this.message});

  final Future<void> Function() onRefresh;
  final String? message;

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
            const SizedBox(height: 12),
            Text(
              message ??
                  'Raporladığın videolar gizlendi. Yenile, kaos geri gelsin.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: NoolColors.lavender,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => onRefresh(),
              child: const Text('Yenile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Demo feed — gerçek URL’ler, muted loop için hazır.
final List<VibePost> _demoPosts = [
  const VibePost(
    id: '1',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    username: '@anon_freshman',
    caption: 'the chaos is real rn lmaooo — who else is lost??',
    distanceLabel: '120m yakınında',
    subtitle: 'Kampüs Orientation',
    trackLabel: 'Charli xcx — 360 (sped up)',
    vibeCountLabel: '1.2k Vibe',
    commentCountLabel: '2.4k',
    avatarColor: Color(0xFFFF8FAB),
  ),
  const VibePost(
    id: '2',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    username: '@anon_gece_glitch44',
    caption: 'gece 03:00 vibe check — kim ayakta?',
    distanceLabel: '340m yakınında',
    subtitle: 'Yakındaki kaos',
    trackLabel: 'original audio — nool_loop',
    vibeCountLabel: '890 Vibe',
    commentCountLabel: '412',
    avatarColor: NoolColors.acid,
  ),
  const VibePost(
    id: '3',
    videoUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    username: '@anon_asit_rakun17',
    caption: 'kaçış planı yok, sadece vibe var.',
    distanceLabel: '80m yakınında',
    subtitle: 'Mahalle chaos',
    trackLabel: 'sped up — midnight run',
    vibeCountLabel: '3.1k Vibe',
    commentCountLabel: '1.1k',
    avatarColor: NoolColors.tangerine,
  ),
  const VibePost(
    id: '4',
    videoUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
    username: '@anon_kayip_pixel09',
    caption: 'bu sokak seni yutuyo — tap if you felt that',
    distanceLabel: '210m yakınında',
    subtitle: 'Street story',
    trackLabel: 'lofi — lost in the grid',
    vibeCountLabel: '2.0k Vibe',
    commentCountLabel: '640',
    avatarColor: Color(0xFF7EC8E3),
  ),
];
