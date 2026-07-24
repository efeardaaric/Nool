import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../models/message_models.dart';
import '../services/messaging_service.dart';
import '../services/social_notification_service.dart';
import '../theme/colors.dart';
import '../screens/chat_screen.dart';
import '../screens/inbox_screen.dart';
import '../screens/other_profile_screen.dart';

/// Layout üstünde hafif banner — yeni istek / mesaj / kabul.
class SocialBannerHost extends StatefulWidget {
  const SocialBannerHost({super.key, required this.child});

  final Widget child;

  @override
  State<SocialBannerHost> createState() => _SocialBannerHostState();
}

class _SocialBannerHostState extends State<SocialBannerHost> {
  StreamSubscription<SocialEvent>? _sub;
  SocialEvent? _banner;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _sub = SocialNotificationService().events.listen(_onEvent);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(SocialEvent event) {
    _hideTimer?.cancel();
    setState(() => _banner = event);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _banner = null);
    });
  }

  Future<void> _openBanner(SocialEvent event) async {
    setState(() => _banner = null);
    switch (event.type) {
      case SocialEventType.squadRequest:
        await Navigator.of(context).push(InboxScreen.route(initialTab: 2));
      case SocialEventType.squadAccepted:
        if (event.relatedUserId != null) {
          try {
            final preview = await MessagingService().openDmWith(
              otherUserId: event.relatedUserId!,
              otherUsername: event.relatedUsername,
            );
            if (!mounted) return;
            await Navigator.of(context).push(ChatScreen.route(preview: preview));
          } catch (_) {
            if (!mounted) return;
            await Navigator.of(context).push(InboxScreen.route(initialTab: 1));
          }
        } else {
          await Navigator.of(context).push(InboxScreen.route(initialTab: 1));
        }
      case SocialEventType.newMessage:
        if (event.conversationId != null && event.relatedUserId != null) {
          final preview = ConversationPreview(
            conversationId: event.conversationId!,
            otherUserId: event.relatedUserId!,
            otherUsername: event.relatedUsername ?? '@anon',
          );
          await Navigator.of(context).push(ChatScreen.route(preview: preview));
        } else if (event.relatedUsername != null) {
          await Navigator.of(context).push(
            OtherProfileScreen.route(
              username: event.relatedUsername!,
              userId: event.relatedUserId,
            ),
          );
        } else {
          await Navigator.of(context).push(InboxScreen.route());
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    final top = MediaQuery.paddingOf(context).top;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (banner != null)
          Positioned(
            left: 14,
            right: 14,
            top: top + 8,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () => _openBanner(banner),
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 280),
                  offset: Offset.zero,
                  curve: Curves.easeOutCubic,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    decoration: BoxDecoration(
                      color: _bannerColor(banner.type),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                banner.title,
                                style: GoogleFonts.syne(
                                  color: NoolColors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                banner.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.syne(
                                  color: NoolColors.ink.withOpacity(0.8),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _banner = null),
                          icon: const NoolIcon(
                            NoolIconData.close,
                            color: NoolColors.ink,
                            size: 18,
                          ),
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

  Color _bannerColor(SocialEventType type) {
    switch (type) {
      case SocialEventType.squadRequest:
        return NoolColors.tangerine;
      case SocialEventType.squadAccepted:
        return NoolColors.acid;
      case SocialEventType.newMessage:
        return NoolColors.lavender;
    }
  }
}
