import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../models/message_models.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';

/// Instagram DM tarzı sohbet thread'i — realtime mesajlar.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.preview});

  final ConversationPreview preview;

  static Route<void> route({required ConversationPreview preview}) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => ChatScreen(preview: preview),
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
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  StreamSubscription<List<ChatMessage>>? _sub;
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String? get _myId => AuthService().currentUser?.id;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await MessagingService().markRead(widget.preview.conversationId);
      await _sub?.cancel();
      _sub = MessagingService()
          .watchMessages(widget.preview.conversationId)
          .listen(
        (items) {
          if (!mounted) return;
          setState(() {
            _messages = items;
            _loading = false;
            _error = null;
          });
          _scrollToEnd();
          MessagingService().markRead(widget.preview.conversationId);
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await MessagingService().sendMessage(
        conversationId: widget.preview.conversationId,
        body: text,
      );
      _input.clear();
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            'Gönderilemedi: $e',
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.acid,
        intensity: 0.7,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
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
                    _HeaderAvatar(url: widget.preview.otherAvatarUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.preview.displayName,
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
              Container(
                height: 3,
                color: NoolColors.ink,
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: NoolLottieView.loading(width: 80, height: 80),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Mesajlar yüklenemedi.',
                                    style: GoogleFonts.syne(
                                      color: NoolColors.tangerine,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _start,
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
                          )
                        : _messages.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    'İlk mesajı sen at.\nSquad chaos başlasın.',
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
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  16,
                                  14,
                                  12,
                                ),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final msg = _messages[index];
                                  final mine = msg.isMine(_myId);
                                  return _Bubble(message: msg, mine: mine);
                                },
                              ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomInset),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: BrutalShadow(
                        offset: const Offset(3, 3),
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          style: GoogleFonts.syne(
                            color: NoolColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Mesaj yaz…',
                            hintStyle: GoogleFonts.syne(
                              color: NoolColors.lavender,
                            ),
                            filled: true,
                            fillColor: NoolColors.lavender.withOpacity(0.14),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide: const BorderSide(
                                color: NoolColors.ink,
                                width: 3,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide: const BorderSide(
                                color: NoolColors.acid,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    BrutalPressable(
                      offset: const Offset(3, 3),
                      enabled: !_sending,
                      onTap: _sending ? null : _send,
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: NoolColors.acid,
                          border: Border.all(color: NoolColors.ink, width: 3),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: NoolLottieView.loading(
                                  width: 28,
                                  height: 28,
                                  compact: true,
                                ),
                              )
                            : const NoolIcon(
                                NoolIconData.send,
                                color: NoolColors.ink,
                                size: 22,
                              ),
                      ),
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

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: NoolColors.acid, width: 2.5),
        color: NoolColors.night,
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              cacheWidth: 72,
              cacheHeight: 72,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: NoolColors.acid.withOpacity(0.2),
                child: const NoolIcon(
                  NoolIconData.person,
                  color: NoolColors.acid,
                  size: 18,
                ),
              ),
            )
          : ColoredBox(
              color: NoolColors.acid.withOpacity(0.2),
              child: const Center(
                child: NoolIcon(
                  NoolIconData.person,
                  color: NoolColors.acid,
                  size: 18,
                ),
              ),
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bg = mine ? NoolColors.acid : NoolColors.lavender.withOpacity(0.22);
    final fg = mine ? NoolColors.ink : NoolColors.white;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: NoolColors.ink, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: NoolColors.ink.withOpacity(mine ? 1 : 0.85),
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: GoogleFonts.syne(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (message.createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatTime(message.createdAt!),
                style: GoogleFonts.syne(
                  color: mine
                      ? NoolColors.ink.withOpacity(0.55)
                      : NoolColors.lavender,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime utc) {
  final local = utc.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
