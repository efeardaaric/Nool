import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../models/notification_item.dart';
import '../services/auth_service.dart';
import '../services/social_notification_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';
import 'direct_chat_screen.dart';
import 'friend_requests_screen.dart';
import 'group_chat_screen.dart';
import 'other_profile_screen.dart';

/// Neo-brutal in-app notification center.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  static Route<void> route() {
    return noolRoute<void>(page: const NotificationsScreen());
  }

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NoolNotification> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthService().isSignedIn) {
      setState(() {
        _loading = false;
        _items = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list =
          await SocialNotificationService.instance.listMyNotifications();
      if (!mounted) return;
      setState(() {
        _items = list;
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

  Future<void> _markAllRead() async {
    try {
      await SocialNotificationService.instance.markRead();
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

  Future<void> _onTap(NoolNotification n) async {
    unawaited(SocialNotificationService.instance.markOneRead(n.id));

    switch (n.type) {
      case 'friend_request':
      case 'friend_accepted':
        final actor = n.actorId;
        if (actor != null) {
          await Navigator.of(context).push(
            OtherProfileScreen.route(
              username: context.s.anonymousUser,
              userId: actor,
            ),
          );
        } else {
          await Navigator.of(context).push(FriendRequestsScreen.route());
        }
        break;
      case 'dm_message':
        final threadId = n.threadId;
        final actor = n.actorId;
        if (threadId != null && actor != null) {
          await Navigator.of(context).push(
            DirectChatScreen.route(
              threadId: threadId,
              otherUserId: actor,
            ),
          );
        }
        break;
      case 'group_message':
        final groupId = n.groupId;
        if (groupId != null) {
          await Navigator.of(context).push(
            GroupChatScreen.route(
              groupId: groupId,
              groupName: n.title,
            ),
          );
        }
        break;
      case 'curiosity':
      case 'system':
      case 'vibe':
      case 'reaction':
        // Teaser / system — stay in center; no deep-link required.
        break;
      default:
        break;
    }

    if (mounted) await _load();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'friend_request':
      case 'friend_accepted':
        return Icons.person_add_alt_1_rounded;
      case 'dm_message':
      case 'group_message':
        return Icons.chat_bubble_rounded;
      case 'vibe':
      case 'reaction':
        return Icons.favorite_rounded;
      case 'curiosity':
        return Icons.radar_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _accentFor(String type) {
    switch (type) {
      case 'friend_request':
        return NoolColors.tangerine;
      case 'friend_accepted':
        return NoolColors.acid;
      case 'dm_message':
      case 'group_message':
        return NoolColors.lavender;
      case 'curiosity':
        return NoolColors.acid;
      default:
        return NoolColors.acid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final hasUnread = _items.any((e) => e.isUnread);

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.acid,
        intensity: 0.85,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: NoolColors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.notificationsTitle,
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    if (hasUnread)
                      BrutalPressable(
                        offset: const Offset(2, 2),
                        onTap: _markAllRead,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: NoolColors.acid,
                            border: Border.all(
                              color: NoolColors.ink,
                              width: 2.5,
                            ),
                          ),
                          child: Text(
                            s.notificationsMarkAll,
                            style: GoogleFonts.syne(
                              color: NoolColors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  s.notificationsSubtitle,
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: NoolLottieView.loading(width: 64, height: 64),
                      )
                    : RefreshIndicator(
                        color: NoolColors.acid,
                        backgroundColor: NoolColors.night,
                        onRefresh: _load,
                        child: _error != null
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _error!,
                                      style: GoogleFonts.syne(
                                        color: NoolColors.tangerine,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : _items.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          24,
                                          48,
                                          24,
                                          24,
                                        ),
                                        child: Column(
                                          children: [
                                            const Icon(
                                              Icons.notifications_none_rounded,
                                              color: NoolColors.acid,
                                              size: 48,
                                            ),
                                            const SizedBox(height: 14),
                                            Text(
                                              s.notificationsEmpty,
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.syne(
                                                color: NoolColors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              s.notificationsEmptyHint,
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.syne(
                                                color: NoolColors.lavender,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      24 + bottom,
                                    ),
                                    itemCount: _items.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, i) {
                                      final n = _items[i];
                                      final accent = _accentFor(n.type);
                                      return Material(
                                        color: n.isUnread
                                            ? Color.lerp(
                                                NoolColors.night,
                                                accent,
                                                0.12,
                                              )
                                            : NoolColors.night,
                                        child: InkWell(
                                          onTap: () => _onTap(n),
                                          child: Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: n.isUnread
                                                    ? accent
                                                    : NoolColors.lavender,
                                                width: 3,
                                              ),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: NoolColors.ink,
                                                  offset: Offset(3, 3),
                                                  blurRadius: 0,
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: accent,
                                                    border: Border.all(
                                                      color: NoolColors.ink,
                                                      width: 2.5,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    _iconFor(n.type),
                                                    color: NoolColors.ink,
                                                    size: 22,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        n.displayTitle(
                                                          english: s.isEnglish,
                                                        ),
                                                        style: GoogleFonts.syne(
                                                          color:
                                                              NoolColors.white,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                      if (n
                                                          .displayBody(
                                                            english:
                                                                s.isEnglish,
                                                          )
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          n.displayBody(
                                                            english:
                                                                s.isEnglish,
                                                          ),
                                                          maxLines: 3,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              GoogleFonts.syne(
                                                            color: NoolColors
                                                                .lavender,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize: 13,
                                                            height: 1.3,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                if (n.isUnread)
                                                  Container(
                                                    width: 10,
                                                    height: 10,
                                                    margin:
                                                        const EdgeInsets.only(
                                                      left: 8,
                                                      top: 4,
                                                    ),
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: NoolColors.acid,
                                                      shape: BoxShape.circle,
                                                      border:
                                                          Border.fromBorderSide(
                                                        BorderSide(
                                                          color: NoolColors.ink,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
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
