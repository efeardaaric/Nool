import 'dart:ui';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../models/squad_group_models.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/squad_group_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_cover_video.dart';
import '../widgets/nool_lottie.dart';
import 'sign_in_screen.dart';

/// Kadro-only dikey video akışı (vibe feed benzeri).
class GroupFeedScreen extends StatefulWidget {
  const GroupFeedScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  static Route<void> route({
    required String groupId,
    required String groupName,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => GroupFeedScreen(
        groupId: groupId,
        groupName: groupName,
      ),
    );
  }

  @override
  State<GroupFeedScreen> createState() => _GroupFeedScreenState();
}

class _GroupFeedScreenState extends State<GroupFeedScreen> {
  late final PageController _pageController;
  List<GroupDrop> _drops = <GroupDrop>[];
  GroupStreak? _streak;
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// İstemci safety net — servis filtresi + gelecek realtime eklemeleri için.
  List<GroupDrop> _filterBlockedLocal(List<GroupDrop> drops) {
    return SquadGroupService().filterBlockedDrops(drops);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = SquadGroupService();
      final results = await Future.wait([
        service.getGroupFeed(widget.groupId),
        service.getGroupStreak(widget.groupId),
      ]);
      if (!mounted) return;
      setState(() {
        // Growable copy — service filters often return fixed-length lists.
        _drops = List<GroupDrop>.from(
          _filterBlockedLocal(results[0] as List<GroupDrop>),
        );
        _streak = results[1] as GroupStreak?;
        _currentIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError(e, context.s);
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NoolColors.acid,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        content: Text(
          message,
          style: GoogleFonts.syne(
            color: NoolColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  void _hideDrop(String id, {required String toast}) {
    final removedIndex = _drops.indexWhere((d) => d.id == id);
    if (removedIndex < 0) return;

    setState(() {
      final next = List<GroupDrop>.from(_drops)..removeAt(removedIndex);
      _drops = next;
      if (_drops.isEmpty) {
        _currentIndex = 0;
        return;
      }
      if (_currentIndex >= _drops.length) {
        _currentIndex = _drops.length - 1;
      } else if (removedIndex < _currentIndex) {
        _currentIndex -= 1;
      }
    });

    if (_drops.isNotEmpty && _pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pageController.hasClients) return;
        _pageController.jumpToPage(_currentIndex);
      });
    }

    _toast(toast);
  }

  void _hideDropsBySender(GroupDrop drop, {required String toast}) {
    final targetId = drop.senderId;
    final targetName = SupabaseService.normalizeUsername(drop.senderUsername);

    setState(() {
      _drops = _drops.where((d) {
        if (d.senderId == targetId) return false;
        if (targetName != null &&
            SupabaseService.normalizeUsername(d.senderUsername) == targetName) {
          return false;
        }
        return true;
      }).toList();
      if (_drops.isEmpty) {
        _currentIndex = 0;
      } else if (_currentIndex >= _drops.length) {
        _currentIndex = _drops.length - 1;
      }
    });

    if (_drops.isNotEmpty && _pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pageController.hasClients) return;
        _pageController.jumpToPage(_currentIndex);
      });
    }

    _toast(toast);
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

  Future<void> _openReportFlow(GroupDrop drop) async {
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
        await _submitReport(drop);
      case _ModerationAction.block:
        await _confirmAndBlock(drop);
    }
  }

  Future<void> _submitReport(GroupDrop drop) async {
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
          videoId: drop.id,
          reason: reason.apiValue,
        );
      }
      _hideDrop(drop.id, toast: s.reportReceived);
    } catch (e) {
      debugPrint('GroupFeed report failed: $e');
      // Still hide locally; never surface raw exception text to users.
      _hideDrop(drop.id, toast: s.reportReceived);
    }
  }

  Future<void> _confirmAndBlock(GroupDrop drop) async {
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
        if (drop.senderId.isNotEmpty) {
          await SupabaseService.instance.blockUser(
            blockedUserId: drop.senderId,
          );
        } else if (drop.senderUsername != null &&
            drop.senderUsername!.trim().isNotEmpty) {
          await SupabaseService.instance.blockUserByUsername(
            drop.senderUsername!,
          );
        }
      }
      _hideDropsBySender(drop, toast: s.userBlockedCampusClean);
    } catch (e) {
      debugPrint('GroupFeed block failed: $e');
      _hideDropsBySender(drop, toast: s.userBlockedCampusClean);
    }
  }

  void _showStreakDialog() {
    final hours = _streak?.hoursUntilExpiry ?? 0;
    final minutes = _streak?.minutesUntilExpiry ?? 0;
    final count = _streak?.currentStreak ?? 0;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: NoolColors.night,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: NoolColors.ink, width: 3.5),
          ),
          title: Text(
            ctx.s.kaosFireTitle,
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            ctx.s.kaosFireBody(
              hours: hours,
              minutes: minutes,
              streak: count,
            ),
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                ctx.s.understood,
                style: GoogleFonts.syne(
                  color: NoolColors.acid,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final canModerate = _drops.isNotEmpty;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(
              child: NoolLottieView.loading(width: 72, height: 72),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.syne(
                    color: NoolColors.tangerine,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else if (_drops.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  context.s.groupFeedEmpty,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _drops.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, index) {
                final drop = _drops[index];
                return _GroupDropPage(
                  key: ValueKey(drop.id),
                  drop: drop,
                  isActive: index == _currentIndex,
                );
              },
            ),
          Positioned(
            top: topPad + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                BrutalPressable(
                  offset: const Offset(3, 3),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NoolColors.acid,
                      border: Border.all(color: NoolColors.ink, width: 3),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: NoolColors.ink,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                BrutalPressable(
                  offset: const Offset(3, 3),
                  onTap: _showStreakDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: NoolColors.acid,
                      border: Border.all(color: NoolColors.ink, width: 3),
                    ),
                    child: Text(
                      '🔥 ${_streak?.currentStreak ?? 0}',
                      style: GoogleFonts.syne(
                        color: NoolColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (canModerate) ...[
                  const SizedBox(width: 8),
                  BrutalPressable(
                    offset: const Offset(3, 3),
                    onTap: () {
                      if (_drops.isEmpty) return;
                      final idx = _currentIndex.clamp(0, _drops.length - 1);
                      _openReportFlow(_drops[idx]);
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: NoolColors.tangerine,
                        border: Border.all(color: NoolColors.ink, width: 3),
                      ),
                      child: const NoolIcon(
                        NoolIconData.flag,
                        color: NoolColors.ink,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupDropPage extends StatefulWidget {
  const _GroupDropPage({
    super.key,
    required this.drop,
    required this.isActive,
  });

  final GroupDrop drop;
  final bool isActive;

  @override
  State<_GroupDropPage> createState() => _GroupDropPageState();
}

class _GroupDropPageState extends State<_GroupDropPage> {
  CachedVideoPlayerPlusController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _muted = !SettingsService.instance.feedSoundOn;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _attach();
  }

  @override
  void didUpdateWidget(covariant _GroupDropPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _attach();
    } else if (!widget.isActive && oldWidget.isActive) {
      _detach();
    }
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    await _detach();
    if (!mounted) return;
    final url = widget.drop.videoUrl.trim();
    final uri = Uri.tryParse(url);
    if (url.isEmpty ||
        uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      setState(() => _failed = true);
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
    setState(() {
      _ready = false;
      _failed = false;
    });

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      final sz = controller.value.size;
      if (sz.width <= 0 || sz.height <= 0) {
        throw StateError('video size unavailable');
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      await controller.play();
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
    } catch (_) {
      await controller.dispose();
      if (_controller == controller) _controller = null;
      if (mounted) {
        setState(() {
          _ready = false;
          _failed = true;
        });
      }
    }
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

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final next = !_muted;
    setState(() => _muted = next);
    try {
      await controller.setVolume(next ? 0 : 1);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom + 16;
    final username = widget.drop.senderUsername ?? context.s.anonymousHandle;
    final handle = username.startsWith('@') ? username : '@$username';

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: NoolColors.night),
        if (_ready && _controller != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleMute,
            child: SizedBox.expand(
              child: NoolCoverVideo(controller: _controller!),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 220,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    NoolColors.night.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: bottomPad,
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: NoolColors.night.withValues(alpha: 0.55),
                  border: Border.all(color: NoolColors.ink, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: NoolColors.ink,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: NoolColors.acid,
                        border: Border.all(color: NoolColors.ink, width: 2),
                      ),
                      child: Text(
                        context.s.squadOnlyChip,
                        style: GoogleFonts.syne(
                          color: NoolColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        NoolAvatar(
                          size: 28,
                          borderWidth: 2,
                          imageUrl: widget.drop.senderAvatarUrl,
                          fallbackInitial: handle,
                          backgroundColor: NoolColors.acid,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            handle,
                            style: GoogleFonts.syne(
                              color: NoolColors.acid,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.drop.caption.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.drop.caption,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.syne(
                          color: NoolColors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
              _ModTile(
                icon: Icons.flag_outlined,
                label: strings.reportThisVideo,
                onTap: () => Navigator.pop(context, _ModerationAction.report),
              ),
              _ModTile(
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
                _ModTile(
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

class _ModTile extends StatelessWidget {
  const _ModTile({
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
        style: GoogleFonts.syne(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      onTap: onTap,
    );
  }
}
