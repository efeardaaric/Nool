import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../screens/friend_requests_screen.dart';
import '../screens/notifications_screen.dart';
import '../services/auth_service.dart';
import '../services/social_notification_service.dart';
import '../theme/colors.dart';
import 'nool_chrome.dart';

/// Bell + optional requests chip for messages / profile top bars.
class NoolNotificationEntry extends StatefulWidget {
  const NoolNotificationEntry({
    super.key,
    this.showRequests = true,
    this.showBell = true,
  });

  final bool showRequests;

  /// Set false to render only the requests chip (e.g. second toolbar row).
  final bool showBell;

  @override
  State<NoolNotificationEntry> createState() => _NoolNotificationEntryState();
}

class _NoolNotificationEntryState extends State<NoolNotificationEntry> {
  StreamSubscription<int>? _sub;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    if (AuthService().isSignedIn) {
      _unread = SocialNotificationService.instance.unreadCount;
      _sub = SocialNotificationService.instance.unreadCountStream.listen((n) {
        if (mounted) setState(() => _unread = n);
      });
      unawaited(SocialNotificationService.instance.fetchUnreadCount());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService().isSignedIn) return const SizedBox.shrink();
    if (!widget.showRequests && !widget.showBell) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showRequests) ...[
          BrutalPressable(
            offset: const Offset(2, 2),
            onTap: () {
              Navigator.of(context).push(FriendRequestsScreen.route());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NoolColors.lavender,
                border: Border.all(color: NoolColors.ink, width: 2.5),
              ),
              child: Text(
                context.s.friendRequestsEntry,
                style: GoogleFonts.syne(
                  color: NoolColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          if (widget.showBell) const SizedBox(width: 8),
        ],
        if (widget.showBell)
          BrutalPressable(
            offset: const Offset(2, 2),
            onTap: () async {
              await Navigator.of(context).push(NotificationsScreen.route());
              unawaited(SocialNotificationService.instance.fetchUnreadCount());
            },
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NoolColors.acid,
                border: Border.all(color: NoolColors.ink, width: 2.5),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_rounded,
                    color: NoolColors.ink,
                    size: 22,
                  ),
                  if (_unread > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: NoolColors.tangerine,
                          border: Border.all(color: NoolColors.ink, width: 1.5),
                        ),
                        child: Text(
                          _unread > 9 ? '9+' : '$_unread',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.syne(
                            color: NoolColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
