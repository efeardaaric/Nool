import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../models/dm_models.dart';
import '../services/auth_service.dart';
import '../services/direct_message_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chat_composer.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';
import 'other_profile_screen.dart';

/// Neo-brutal 1:1 direkt sohbet.
class DirectChatScreen extends StatefulWidget {
  const DirectChatScreen({
    super.key,
    required this.threadId,
    required this.otherUserId,
    this.otherUsername,
    this.otherAvatarUrl,
  });

  final String threadId;
  final String otherUserId;
  final String? otherUsername;
  final String? otherAvatarUrl;

  static Route<void> route({
    required String threadId,
    required String otherUserId,
    String? otherUsername,
    String? otherAvatarUrl,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => DirectChatScreen(
        threadId: threadId,
        otherUserId: otherUserId,
        otherUsername: otherUsername,
        otherAvatarUrl: otherAvatarUrl,
      ),
    );
  }

  /// Thread yoksa oluşturur, sonra sohbeti açar.
  static Future<void> openWithUser(
    BuildContext context, {
    required String otherUserId,
    String? otherUsername,
    String? otherAvatarUrl,
  }) async {
    final thread = await DirectMessageService().getOrCreateThread(otherUserId);
    if (!context.mounted) return;
    final name = otherUsername ?? thread.otherProfile?.username;
    final avatar = otherAvatarUrl ?? thread.otherProfile?.avatarUrl;
    await Navigator.of(context).push(
      DirectChatScreen.route(
        threadId: thread.id,
        otherUserId: otherUserId,
        otherUsername: name,
        otherAvatarUrl: avatar,
      ),
    );
  }

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<DmMessage> _messages = const [];
  StreamSubscription<List<DmMessage>>? _sub;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String get _title {
    final name =
        widget.otherUsername ?? AppStrings.fromSettings().anonymousHandle;
    return name.startsWith('@') ? name : '@$name';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _subscribe() {
    try {
      _sub = DirectMessageService().watchMessages(widget.threadId).listen(
        (list) {
          if (!mounted) return;
          setState(() => _messages = list);
          _scrollToEnd();
        },
        onError: (e) {
          debugPrint('DM watch: $e');
        },
      );
    } catch (e) {
      debugPrint('DM subscribe failed: $e');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await DirectMessageService().listMessages(widget.threadId);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError(e, context.s);
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await DirectMessageService().sendMessage(
        threadId: widget.threadId,
        body: text,
      );
      if (!mounted) return;
      _input.clear();
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        _sending = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
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

  void _openProfile() {
    final name = widget.otherUsername;
    if (name == null || name.isEmpty) return;
    Navigator.of(context).push(
      OtherProfileScreen.route(
        username: name,
        userId: widget.otherUserId,
      ),
    );
  }

  void _pop() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService().currentUser?.id;
    // Scaffold already shrinks for the keyboard via resizeToAvoidBottomInset.
    // Do NOT also pad with viewInsets — that double-counts and crushes the
    // Expanded message list (same class of bug as camera caption shift).

    return Scaffold(
      backgroundColor: NoolColors.night,
      resizeToAvoidBottomInset: true,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.acid,
        intensity: 0.55,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                title: _title,
                avatarUrl: widget.otherAvatarUrl,
                onBack: _pop,
                onProfile: _openProfile,
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: NoolLottieView.loading(width: 64, height: 64),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.syne(
                                      color: NoolColors.tangerine,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  BrutalPressable(
                                    offset: const Offset(2, 2),
                                    onTap: _load,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: NoolColors.acid,
                                        border: Border.all(
                                          color: NoolColors.ink,
                                          width: 3,
                                        ),
                                      ),
                                      child: Text(
                                        context.s.retry,
                                        style: GoogleFonts.syne(
                                          color: NoolColors.ink,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _messages.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Text(
                                    context.s.dmChatEmpty,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.syne(
                                      color: NoolColors.lavender,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _scroll,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                // Extra right/bottom for neo-brutal bubble shadows.
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  20,
                                  16,
                                ),
                                itemCount: _messages.length,
                                itemBuilder: (context, i) {
                                  final msg = _messages[i];
                                  final mine = msg.senderId == me;
                                  return _Bubble(message: msg, mine: mine);
                                },
                              ),
              ),
              NoolChatComposer(
                controller: _input,
                hintText: context.s.dmChatHint,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onBack,
    required this.onProfile,
    this.avatarUrl,
  });

  final String title;
  final String? avatarUrl;
  final VoidCallback onBack;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          BrutalPressable(
            offset: const Offset(3, 3),
            onTap: onBack,
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
            child: BrutalPressable(
              offset: const Offset(2, 2),
              onTap: onProfile,
              child: Row(
                children: [
                  NoolAvatar(
                    size: 40,
                    borderWidth: 2.5,
                    imageUrl: avatarUrl,
                    showShadow: true,
                    fallbackIconSize: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.syne(
                        color: NoolColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final DmMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: mine ? NoolColors.acid : NoolColors.night,
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
          message.body,
          softWrap: true,
          style: GoogleFonts.syne(
            color: mine ? NoolColors.ink : NoolColors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
