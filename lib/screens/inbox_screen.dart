import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../models/message_models.dart';
import '../models/squad_models.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../services/profile_service.dart';
import '../services/social_notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';
import 'chat_screen.dart';
import 'other_profile_screen.dart';
import 'sign_in_screen.dart';

/// Instagram tarzı inbox: Mesajlar + Squad + istekler.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.initialTab = 0});

  /// 0 = sohbetler, 1 = squad, 2 = istekler.
  final int initialTab;

  static Route<void> route({int initialTab = 0}) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => InboxScreen(initialTab: initialTab),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<ConversationPreview> _conversations = const [];
  List<SquadEdge> _squad = const [];
  List<SquadEdge> _requests = const [];
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _inboxSub;
  String? _dmBusyId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    SocialNotificationService().markAllSeen();
    _bootstrap();
  }

  @override
  void dispose() {
    _inboxSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!AuthService().isSignedIn) {
      setState(() {
        _loading = false;
        _error = 'Mesajlar için giriş yapmalısın.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final convs = await MessagingService().listConversations();
      final friends = await ProfileService().getMySquadList();
      var reqs = await ProfileService().getPendingSquadRequests();
      try {
        final blocked = await ProfileService().blockedUsernameKeys();
        if (blocked.isNotEmpty) {
          reqs = reqs
              .where((e) {
                final name = e.otherProfile?.username;
                if (name == null) return true;
                return !ProfileService.usernameMatchesBlocked(name, blocked);
              })
              .toList(growable: false);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _conversations = convs;
        _squad = friends;
        _requests = reqs;
        _loading = false;
      });

      await _inboxSub?.cancel();
      _inboxSub = MessagingService().watchInboxChanges().listen((_) {
        _softRefresh();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _softRefresh() async {
    try {
      final convs = await MessagingService().listConversations();
      final friends = await ProfileService().getMySquadList();
      var reqs = await ProfileService().getPendingSquadRequests();
      try {
        final blocked = await ProfileService().blockedUsernameKeys();
        if (blocked.isNotEmpty) {
          reqs = reqs
              .where((e) {
                final name = e.otherProfile?.username;
                if (name == null) return true;
                return !ProfileService.usernameMatchesBlocked(name, blocked);
              })
              .toList(growable: false);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _conversations = convs;
        _squad = friends;
        _requests = reqs;
        _error = null;
      });
    } catch (_) {}
  }

  Future<void> _accept(SquadEdge edge) async {
    try {
      await ProfileService().acceptSquadRequest(edge.id);
      SocialNotificationService().decrementUnread();
      if (!mounted) return;
      _toast('Squad kuruldu.');
      await _softRefresh();
    } catch (e) {
      _toast('Kabul edilemedi: $e');
    }
  }

  Future<void> _reject(SquadEdge edge) async {
    try {
      await ProfileService().rejectSquadRequest(edge.id);
      SocialNotificationService().decrementUnread();
      if (!mounted) return;
      _toast('İstek reddedildi.');
      await _softRefresh();
    } catch (e) {
      _toast('Reddedilemedi: $e');
    }
  }

  Future<void> _openChat(ConversationPreview preview) async {
    await Navigator.of(context).push(ChatScreen.route(preview: preview));
    if (mounted) _softRefresh();
  }

  Future<void> _openDmWithFriend(SquadEdge edge) async {
    final myId = AuthService().currentUser?.id;
    if (myId == null) return;
    final otherId = edge.senderId == myId ? edge.receiverId : edge.senderId;
    final profile = edge.otherProfile;
    final name = profile?.username ?? '@anon';
    final display = name.startsWith('@') ? name : '@$name';

    setState(() => _dmBusyId = otherId);
    try {
      final preview = await MessagingService().openDmWith(
        otherUserId: otherId,
        otherUsername: display,
        otherAvatarUrl: profile?.avatarUrl,
      );
      if (!mounted) return;
      await Navigator.of(context).push(ChatScreen.route(preview: preview));
      if (mounted) _softRefresh();
    } catch (e) {
      _toast('Sohbet açılamadı: $e');
    } finally {
      if (mounted) setState(() => _dmBusyId = null);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NoolColors.acid,
        content: Text(
          message,
          style: GoogleFonts.syne(
            color: NoolColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.lavender,
        intensity: 0.85,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const NoolIcon(
                        NoolIconData.back,
                        color: NoolColors.white,
                        size: 22,
                      ),
                    ),
                    Text(
                      'MESAJLAR',
                      style: GoogleFonts.syne(
                        color: NoolColors.acid,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    if (_requests.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: NoolColors.tangerine,
                          border: Border.all(color: NoolColors.ink, width: 2),
                        ),
                        child: Text(
                          '${_requests.length}',
                          style: GoogleFonts.syne(
                            color: NoolColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: NoolColors.ink, width: 3),
                  ),
                  child: TabBar(
                    controller: _tabs,
                    indicator: const BoxDecoration(color: NoolColors.acid),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: NoolColors.ink,
                    unselectedLabelColor: NoolColors.lavender,
                    labelStyle: GoogleFonts.syne(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: GoogleFonts.syne(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    tabs: [
                      const Tab(text: 'Sohbetler'),
                      Tab(
                        text: _squad.isEmpty
                            ? 'Squad'
                            : 'Squad (${_squad.length})',
                      ),
                      Tab(
                        text: _requests.isEmpty
                            ? 'İstekler'
                            : 'İstekler (${_requests.length})',
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: !AuthService().isSignedIn
                    ? _SignInGate(
                        onSignIn: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SignInScreen(),
                            ),
                          );
                          await _bootstrap();
                        },
                      )
                    : _loading
                        ? const Center(
                            child: NoolLottieView.loading(
                              width: 96,
                              height: 96,
                            ),
                          )
                        : _error != null
                            ? _ErrorState(
                                message: _error!,
                                onRetry: _bootstrap,
                              )
                            : TabBarView(
                                controller: _tabs,
                                children: [
                                  _ConversationsTab(
                                    items: _conversations,
                                    onRefresh: _bootstrap,
                                    onOpen: _openChat,
                                  ),
                                  _SquadFriendsTab(
                                    items: _squad,
                                    busyId: _dmBusyId,
                                    onRefresh: _bootstrap,
                                    onMessage: _openDmWithFriend,
                                  ),
                                  _RequestsTab(
                                    items: _requests,
                                    onRefresh: _bootstrap,
                                    onAccept: _accept,
                                    onReject: _reject,
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

class _SignInGate extends StatelessWidget {
  const _SignInGate({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mesajlar için hesabını güvenceye al.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            BrutalShadow(
              offset: const Offset(4, 4),
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onSignIn,
                  child: const Text('Giriş Yap'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bağlantı kopuk veya sunucu yanıt vermedi.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.tangerine,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Tekrar dene',
                style: GoogleFonts.syne(
                  color: NoolColors.acid,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationsTab extends StatelessWidget {
  const _ConversationsTab({
    required this.items,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<ConversationPreview> items;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationPreview> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: NoolColors.acid,
        backgroundColor: NoolColors.night,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Text(
              'Henüz sohbet yok.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Squad sekmesinden arkadaşınla yazışmaya başla.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: NoolColors.acid,
      backgroundColor: NoolColors.night,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return _ConversationTile(
            preview: item,
            onTap: () => onOpen(item),
          );
        },
      ),
    );
  }
}

class _SquadFriendsTab extends StatelessWidget {
  const _SquadFriendsTab({
    required this.items,
    required this.onRefresh,
    required this.onMessage,
    this.busyId,
  });

  final List<SquadEdge> items;
  final Future<void> Function() onRefresh;
  final ValueChanged<SquadEdge> onMessage;
  final String? busyId;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: NoolColors.acid,
        backgroundColor: NoolColors.night,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Text(
              'Squad’ın boş.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Birinin profilinden SQUAD UP! ile istek at.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final myId = AuthService().currentUser?.id;

    return RefreshIndicator(
      color: NoolColors.acid,
      backgroundColor: NoolColors.night,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final edge = items[index];
          final profile = edge.otherProfile;
          final name = profile?.username ?? '@anon';
          final display = name.startsWith('@') ? name : '@$name';
          final otherId =
              edge.senderId == myId ? edge.receiverId : edge.senderId;
          final busy = busyId == otherId;

          return BrutalShadow(
            offset: const Offset(3, 3),
            child: Material(
              color: NoolColors.lavender.withOpacity(0.12),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    OtherProfileScreen.route(
                      username: display,
                      userId: otherId,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: NoolColors.ink, width: 3),
                  ),
                  child: Row(
                    children: [
                      _AvatarBubble(url: profile?.avatarUrl, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              display,
                              style: GoogleFonts.syne(
                                color: NoolColors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'Squad',
                              style: GoogleFonts.syne(
                                color: NoolColors.lavender,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      BrutalPressable(
                        offset: const Offset(2, 2),
                        enabled: !busy,
                        onTap: busy ? null : () => onMessage(edge),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NoolColors.acid,
                            border:
                                Border.all(color: NoolColors.ink, width: 2.5),
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: NoolColors.ink,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const NoolIcon(
                                      NoolIconData.send,
                                      color: NoolColors.ink,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'DM',
                                      style: GoogleFonts.syne(
                                        color: NoolColors.ink,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
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
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.preview, required this.onTap});

  final ConversationPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previewText = preview.lastMessagePreview.isEmpty
        ? 'Sohbet başlat — ilk mesajı yaz.'
        : preview.lastMessagePreview;
    final time = preview.lastMessageAt;

    return BrutalPressable(
      offset: const Offset(3, 3),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: NoolColors.lavender.withOpacity(0.12),
          border: Border.all(color: NoolColors.ink, width: 3),
        ),
        child: Row(
          children: [
            _AvatarBubble(url: preview.otherAvatarUrl, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.syne(
                            color: NoolColors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (time != null)
                        Text(
                          _relativeTime(time),
                          style: GoogleFonts.syne(
                            color: NoolColors.lavender,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.items,
    required this.onRefresh,
    required this.onAccept,
    required this.onReject,
  });

  final List<SquadEdge> items;
  final Future<void> Function() onRefresh;
  final ValueChanged<SquadEdge> onAccept;
  final ValueChanged<SquadEdge> onReject;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: NoolColors.acid,
        backgroundColor: NoolColors.night,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Text(
              'Bekleyen istek yok.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: NoolColors.acid,
      backgroundColor: NoolColors.night,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final edge = items[index];
          final profile = edge.otherProfile;
          final name = profile?.username ?? '@anon';
          final display = name.startsWith('@') ? name : '@$name';

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NoolColors.lavender.withOpacity(0.12),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          OtherProfileScreen.route(
                            username: display,
                            userId: edge.senderId,
                          ),
                        );
                      },
                      child: _AvatarBubble(
                        url: profile?.avatarUrl,
                        size: 44,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            display,
                            style: GoogleFonts.syne(
                              color: NoolColors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Squad isteği gönderdi',
                            style: GoogleFonts.syne(
                              color: NoolColors.lavender,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BrutalPressable(
                        offset: const Offset(3, 3),
                        onTap: () => onAccept(edge),
                        child: Container(
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NoolColors.acid,
                            border:
                                Border.all(color: NoolColors.ink, width: 3),
                          ),
                          child: Text(
                            'Kabul',
                            style: GoogleFonts.syne(
                              color: NoolColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BrutalPressable(
                        offset: const Offset(3, 3),
                        onTap: () => onReject(edge),
                        child: Container(
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NoolColors.night,
                            border: Border.all(
                              color: NoolColors.tangerine,
                              width: 3,
                            ),
                          ),
                          child: Text(
                            'Reddet',
                            style: GoogleFonts.syne(
                              color: NoolColors.tangerine,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: NoolColors.night,
        border: Border.all(color: NoolColors.acid, width: 2.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              cacheWidth: 96,
              cacheHeight: 96,
              errorBuilder: (_, __, ___) => const _AvatarFallbackIcon(),
            )
          : const _AvatarFallbackIcon(),
    );
  }
}

class _AvatarFallbackIcon extends StatelessWidget {
  const _AvatarFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NoolColors.acid.withOpacity(0.18),
      child: const Center(
        child: NoolIcon(
          NoolIconData.person,
          color: NoolColors.acid,
          size: 22,
        ),
      ),
    );
  }
}

String _relativeTime(DateTime utc) {
  final local = utc.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'şimdi';
  if (diff.inMinutes < 60) return '${diff.inMinutes}dk';
  if (diff.inHours < 24) return '${diff.inHours}sa';
  if (diff.inDays < 7) return '${diff.inDays}g';
  return '${local.day}.${local.month}';
}
