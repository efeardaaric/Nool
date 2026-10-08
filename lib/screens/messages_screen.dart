import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../models/dm_models.dart';
import '../models/squad_group_models.dart';
import '../models/squad_models.dart';
import '../services/auth_service.dart';
import '../services/direct_message_service.dart';
import '../services/profile_service.dart';
import '../services/squad_group_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import '../widgets/nool_notification_entry.dart';
import 'create_group_screen.dart';
import 'direct_chat_screen.dart';
import 'group_chat_screen.dart';
import 'other_profile_screen.dart';
import 'people_search_screen.dart';

/// Mesaj sekmesi — Direkt 1:1 + Kadrolar + squad listesi.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    this.isActive = true,
    this.onSecureAccount,
  });

  final bool isActive;
  final Future<void> Function()? onSecureAccount;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<SquadEdge> _squads = const [];
  List<SquadGroup> _groups = const [];
  List<DmThread> _threads = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(covariant MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _load();
  }

  Future<void> _load() async {
    if (!AuthService().isSignedIn) {
      setState(() {
        _loading = false;
        _squads = const [];
        _groups = const [];
        _threads = const [];
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final squads = await ProfileService().getMySquadList();
      List<SquadGroup> groups = const [];
      try {
        groups = await SquadGroupService().listMyGroupsWithStreaks();
      } catch (e) {
        debugPrint('listMyGroupsWithStreaks: $e');
      }
      List<DmThread> threads = const [];
      try {
        threads = await DirectMessageService().listMyThreads();
      } catch (e) {
        // Migration henüz yoksa kadro/squad yine gösterilsin.
        debugPrint('listMyThreads: $e');
      }
      if (!mounted) return;
      setState(() {
        _squads = squads;
        _groups = groups;
        _threads = threads;
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

  Future<void> _openCreateGroup() async {
    await Navigator.of(context).push(CreateGroupScreen.route());
    if (mounted) await _load();
  }

  Future<void> _openGroup(SquadGroup group) async {
    await Navigator.of(context).push<bool?>(
      GroupChatScreen.route(
        groupId: group.id,
        groupName: group.name,
        createdBy: group.createdBy,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _confirmDeleteGroup(SquadGroup group) async {
    final me = AuthService().currentUser?.id;
    if (!group.isOwnedBy(me)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            context.s.deleteKadroOwnerOnly,
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

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
          s.deleteKadroTitle,
          style: GoogleFonts.syne(
            color: NoolColors.tangerine,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        content: Text(
          s.deleteKadroBody,
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
              s.cancel,
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
                  s.deleteKadroConfirm,
                  style: GoogleFonts.syne(
                    color: NoolColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await SquadGroupService().deleteSquadCircle(group.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.acid,
          content: Text(
            context.s.deleteKadroDone,
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            userFacingError(e, context.s),
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openDmThread(DmThread thread) async {
    final me = AuthService().currentUser?.id;
    if (me == null) return;
    final other = thread.otherProfile;
    await Navigator.of(context).push(
      DirectChatScreen.route(
        threadId: thread.id,
        otherUserId: thread.otherUserId(me),
        otherUsername: other?.username,
        otherAvatarUrl: other?.avatarUrl,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openDmWithUser({
    required String userId,
    String? username,
    String? avatarUrl,
  }) async {
    try {
      await DirectChatScreen.openWithUser(
        context,
        otherUserId: userId,
        otherUsername: username,
        otherAvatarUrl: avatarUrl,
      );
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            userFacingError(e, context.s),
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = AuthService().isSignedIn;
    final bottomPad = MediaQuery.paddingOf(context).bottom + 96;
    final emptyAll = _squads.isEmpty && _groups.isEmpty && _threads.isEmpty;

    return NoolAtmosphere(
      accent: AtmosphereAccent.acid,
      intensity: 0.75,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              color: NoolColors.acid,
              backgroundColor: NoolColors.night,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
                children: [
                  // Row 1: brand + icon actions only (text chips overflow on SE).
                  Row(
                    children: [
                      const NoolLogoMark(size: 32, border: true, shadow: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.s.messagesTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.syne(
                            color: NoolColors.acid,
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      if (signedIn) ...[
                        const SizedBox(width: 8),
                        // Bell only here — "İstekler" chip moved below.
                        const NoolNotificationEntry(showRequests: false),
                        const SizedBox(width: 8),
                        BrutalPressable(
                          offset: const Offset(3, 3),
                          onTap: () {
                            Navigator.of(context)
                                .push(PeopleSearchScreen.route());
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: NoolColors.tangerine,
                              border: Border.all(
                                color: NoolColors.ink,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.person_search_rounded,
                              color: NoolColors.ink,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          context.s.messagesSubtitle,
                          style: GoogleFonts.syne(
                            color: NoolColors.lavender,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (signedIn) ...[
                        const SizedBox(width: 8),
                        const NoolNotificationEntry(
                          showRequests: true,
                          showBell: false,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (!signedIn)
                    _GateCard(onSecure: widget.onSecureAccount)
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(
                        child: NoolLottieView.loading(width: 72, height: 72),
                      ),
                    )
                  else if (_error != null)
                    Text(
                      _error!,
                      style: GoogleFonts.syne(
                        color: NoolColors.tangerine,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (emptyAll)
                    Padding(
                      padding: const EdgeInsets.only(top: 36),
                      child: Column(
                        children: [
                          const NoolIcon(
                            NoolIconData.send,
                            color: NoolColors.acid,
                            size: 48,
                            withBrutalShadow: true,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.s.noSquadYet,
                            style: GoogleFonts.syne(
                              color: NoolColors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.s.noSquadHint,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.syne(
                              color: NoolColors.lavender,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 18),
                          BrutalPressable(
                            offset: const Offset(3, 3),
                            onTap: _openCreateGroup,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: NoolColors.acid,
                                border: Border.all(
                                  color: NoolColors.ink,
                                  width: 3.5,
                                ),
                              ),
                              child: Text(
                                context.s.createCircleCta,
                                style: GoogleFonts.syne(
                                  color: NoolColors.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if (_threads.isNotEmpty) ...[
                      Text(
                        context.s.dmSection,
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final thread in _threads) ...[
                        _DmThreadTile(
                          thread: thread,
                          onTap: () => _openDmThread(thread),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 12),
                    ],
                    if (_groups.isNotEmpty) ...[
                      Text(
                        context.s.kadrolarSection,
                        style: GoogleFonts.syne(
                          color: NoolColors.tangerine,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final group in _groups) ...[
                        _GroupTile(
                          group: group,
                          onTap: () => _openGroup(group),
                          onLongPress: () => _confirmDeleteGroup(group),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 12),
                    ],
                    if (_squads.isNotEmpty) ...[
                      Text(
                        context.s.squadsSection,
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final edge in _squads) ...[
                        _SquadThreadTile(
                          edge: edge,
                          onMessage: () {
                            final other = edge.otherProfile;
                            final id = other?.id;
                            if (id == null || id.isEmpty) return;
                            _openDmWithUser(
                              userId: id,
                              username: other?.username,
                              avatarUrl: other?.avatarUrl,
                            );
                          },
                          onProfile: () {
                            final name = edge.otherProfile?.username;
                            if (name == null || name.isEmpty) return;
                            Navigator.of(context).push(
                              OtherProfileScreen.route(username: name),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ],
              ),
            ),
            if (signedIn && !_loading && _error == null)
              Positioned(
                right: 20,
                bottom: MediaQuery.paddingOf(context).bottom + 88,
                child: BrutalPressable(
                  offset: const Offset(3, 3),
                  onTap: _openCreateGroup,
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NoolColors.acid,
                      border: Border.all(color: NoolColors.ink, width: 3.5),
                    ),
                    child: Text(
                      '+',
                      style: GoogleFonts.syne(
                        color: NoolColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        height: 1,
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

class _GateCard extends StatelessWidget {
  const _GateCard({this.onSecure});

  final Future<void> Function()? onSecure;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NoolColors.night,
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
            context.s.loginRequired,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.s.messagesNeedAccount,
            style: GoogleFonts.syne(
              color: NoolColors.lavender,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: NoolColors.acid,
            child: InkWell(
              onTap: onSecure == null ? null : () => onSecure!(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: NoolColors.ink, width: 3),
                ),
                alignment: Alignment.center,
                child: Text(
                  context.s.secureAccount,
                  style: GoogleFonts.syne(
                    color: NoolColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DmThreadTile extends StatelessWidget {
  const _DmThreadTile({required this.thread, required this.onTap});

  final DmThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final other = thread.otherProfile;
    final name = other?.username ?? context.s.anonymousHandle;
    final handle = name.startsWith('@') ? name : '@$name';
    final preview = thread.lastMessagePreview?.trim();
    final subtitle = (preview != null && preview.isNotEmpty)
        ? preview
        : context.s.dmNoPreview;

    return BrutalPressable(
      offset: const Offset(3, 3),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: NoolColors.night,
          border: Border.all(color: NoolColors.ink, width: 3.5),
          boxShadow: const [
            BoxShadow(
              color: NoolColors.ink,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            NoolAvatar(
              size: 48,
              borderWidth: 2.5,
              imageUrl: other?.avatarUrl,
              showShadow: true,
              fallbackIconSize: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const NoolIcon(
              NoolIconData.send,
              color: NoolColors.acid,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.onTap,
    this.onLongPress,
  });

  final SquadGroup group;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final streak = group.streak?.currentStreak ?? 0;
    final urgent = group.streak?.isExpiringSoon ?? false;

    return BrutalPressable(
      offset: const Offset(3, 3),
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: NoolColors.lavender.withValues(alpha: 0.14),
              border: Border.all(color: NoolColors.ink, width: 3.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
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
                    group.name.isNotEmpty
                        ? group.name.substring(0, 1).toUpperCase()
                        : 'K',
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.syne(
                          color: NoolColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.s.kadrolarTileSub(streak: streak),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _KaosFireBadge(streak: streak, urgent: urgent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sağ taraftaki Kaos Ateşi rozeti — acilse tangerine + pulse.
class _KaosFireBadge extends StatefulWidget {
  const _KaosFireBadge({required this.streak, required this.urgent});

  final int streak;
  final bool urgent;

  @override
  State<_KaosFireBadge> createState() => _KaosFireBadgeState();
}

class _KaosFireBadgeState extends State<_KaosFireBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _KaosFireBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urgent != widget.urgent) _syncPulse();
  }

  void _syncPulse() {
    if (widget.urgent) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      )..repeat(reverse: true);
    } else {
      _pulse?.stop();
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.urgent ? NoolColors.tangerine : NoolColors.acid;
    final label = '🔥 ${widget.streak}';

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent,
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
        label,
        style: GoogleFonts.syne(
          color: NoolColors.ink,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );

    final ctrl = _pulse;
    if (ctrl == null) return badge;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, child) {
        final t = ctrl.value;
        return Opacity(
          opacity: 0.55 + (t * 0.45),
          child: Transform.scale(
            scale: 0.94 + (t * 0.08),
            child: child,
          ),
        );
      },
      child: badge,
    );
  }
}

class _SquadThreadTile extends StatelessWidget {
  const _SquadThreadTile({
    required this.edge,
    required this.onMessage,
    required this.onProfile,
  });

  final SquadEdge edge;
  final VoidCallback onMessage;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final other = edge.otherProfile;
    final name = other?.username ?? context.s.anonymousHandle;
    final avatar = other?.avatarUrl;

    return BrutalPressable(
      offset: const Offset(3, 3),
      onTap: onMessage,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: NoolColors.night,
          border: Border.all(color: NoolColors.ink, width: 3),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onProfile,
              child: NoolAvatar(
                size: 48,
                borderWidth: 2.5,
                imageUrl: avatar,
                showShadow: true,
                fallbackIconSize: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.startsWith('@') ? name : '@$name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.s.dmOpenChat,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const NoolIcon(
              NoolIconData.send,
              color: NoolColors.acid,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
