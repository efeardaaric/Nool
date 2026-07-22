import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/comment_item.dart';
import '../services/onboarding_service.dart';
import '../services/profanity_filter.dart';
import '../services/supabase_service.dart';
import '../icons/nool_emojis.dart';
import '../icons/nool_icons.dart';
import '../theme/colors.dart';
import '../screens/other_profile_screen.dart';
import '../widgets/nool_lottie.dart';

/// Alttan açılan canlı yorum paneli.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String videoId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CommentsSheet(videoId: videoId),
      );
    },
  );
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.videoId});

  final String videoId;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  StreamSubscription<List<CommentItem>>? _subscription;
  List<CommentItem> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  bool _offlineMode = false;
  String? _error;
  String? _filterWarning;
  Timer? _warningTimer;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _warningTimer?.cancel();
    _subscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    final supabase = SupabaseService.instance;
    if (!supabase.isReady) {
      setState(() {
        _offlineMode = true;
        _loading = false;
        _comments = _demoComments(widget.videoId);
      });
      return;
    }

    try {
      await _subscription?.cancel();
      _subscription = supabase.watchComments(widget.videoId).listen(
        (items) {
          if (!mounted) return;
          setState(() {
            _comments = items;
            _loading = false;
            _error = null;
          });
          _scrollToEnd();
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Yorumlar yüklenemedi.';
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Realtime bağlanamadı.';
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _flashFilterWarning() {
    _warningTimer?.cancel();
    setState(() => _filterWarning = ProfanityFilter.blockedMessage);
    _warningTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _filterWarning = null);
    });
  }

  Future<void> _submit() async {
    if (_sending) return;
    final raw = _inputController.text;
    final text = raw.trim();
    if (text.isEmpty) return;

    if (ProfanityFilter.containsBlocked(text)) {
      _flashFilterWarning();
      return;
    }

    setState(() {
      _sending = true;
      _filterWarning = null;
    });

    try {
      if (_offlineMode || !SupabaseService.instance.isReady) {
        final onboard = await OnboardingService.ensureOnboarded();
        setState(() {
          _comments = [
            ..._comments,
            CommentItem(
              id: const Uuid().v4(),
              videoId: widget.videoId,
              deviceId: onboard.deviceId,
              username: onboard.username,
              body: text,
              createdAt: DateTime.now(),
            ),
          ];
          _inputController.clear();
        });
        _scrollToEnd();
        return;
      }

      final onboard = await OnboardingService.ensureOnboarded();
      await SupabaseService.instance.postComment(
        videoId: widget.videoId,
        deviceId: onboard.deviceId,
        username: onboard.username,
        body: text,
      );
      _inputController.clear();
      _focusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            'Gönderilemedi: $e',
            style: const TextStyle(
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
    final height = MediaQuery.sizeOf(context).height * 0.6;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: NoolColors.night.withOpacity(0.82),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NoolColors.lavender.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Row(
                    children: [
                      Text(
                        'Yorumlar',
                        style: GoogleFonts.syne(
                          color: NoolColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_comments.length}',
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      if (_offlineMode)
                        Text(
                          'offline demo',
                          style: GoogleFonts.syne(
                            color: NoolColors.lavender,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _buildList()),
                if (_filterWarning != null) _FilterBanner(message: _filterWarning!),
                NoolEmojiPicker(
                  size: 28,
                  onSelected: (emoji) {
                    final c = _inputController;
                    final text = c.text;
                    final sel = c.selection;
                    final insertAt =
                        sel.isValid ? sel.start : text.length;
                    final next =
                        text.replaceRange(insertAt, insertAt, emoji.token);
                    c.value = TextEditingValue(
                      text: next,
                      selection: TextSelection.collapsed(
                        offset: insertAt + emoji.token.length,
                      ),
                    );
                    _focusNode.requestFocus();
                  },
                ),
                _Composer(
                  controller: _inputController,
                  focusNode: _focusNode,
                  sending: _sending,
                  onSend: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: const NoolLottieView.loading(
          width: 48,
          height: 48,
          compact: true,
        ),
      );
    }

    if (_error != null && _comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.syne(color: NoolColors.lavender),
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return Center(
        child: Text(
          'İlk yorumu sen bırak — pozitif kal.',
          style: GoogleFonts.syne(
            color: NoolColors.lavender,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final comment = _comments[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          OtherProfileScreen.route(
                            username: comment.username,
                            deviceId: comment.deviceId.isEmpty
                                ? null
                                : comment.deviceId,
                          ),
                        );
                      },
                      child: Text(
                        comment.username,
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    NoolEmojiText(
                      comment.body,
                      emojiSize: 18,
                      style: GoogleFonts.syne(
                        color: NoolColors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                comment.relativeTime,
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterBanner extends StatelessWidget {
  const _FilterBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2A0A12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFF2D55), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2D55).withOpacity(0.55),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Text(
          message,
          style: GoogleFonts.syne(
            color: const Color(0xFFFF6B8A),
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 10 + bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: NoolColors.night,
                border: Border.all(color: NoolColors.ink, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                cursorColor: NoolColors.acid,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Yorumunu bırak…',
                  hintStyle: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: NoolColors.acid,
            child: InkWell(
              onTap: sending ? null : onSend,
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: NoolColors.ink, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: NoolColors.ink,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: sending
                    ? const NoolLottieView.loading(
                        width: 24,
                        height: 24,
                        compact: true,
                      )
                    : const NoolIcon(
                        NoolIconData.send,
                        color: NoolColors.ink,
                        size: 22,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<CommentItem> _demoComments(String videoId) {
  final now = DateTime.now();
  return [
    CommentItem(
      id: 'd1',
      videoId: videoId,
      deviceId: 'demo',
      username: '@anon_kutuphane_hayaleti',
      body: 'bu drop efsane ya ${NoolEmojiData.cry.token}${NoolEmojiData.fire.token}',
      createdAt: now.subtract(const Duration(minutes: 4)),
    ),
    CommentItem(
      id: 'd2',
      videoId: videoId,
      deviceId: 'demo',
      username: '@anon_yemekhane_samurai',
      body: 'kimse beni görmedi dimi ${NoolEmojiData.cool.token}',
      createdAt: now.subtract(const Duration(minutes: 1)),
    ),
  ];
}
