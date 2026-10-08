import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../models/squad_group_models.dart';
import '../services/auth_service.dart';
import '../services/squad_group_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_chat_composer.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';
import 'camera_screen.dart';
import 'group_feed_screen.dart';

/// Neo-brutal kadro sohbet odası + Kaos Ateşi + grup drop.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.createdBy,
  });

  final String groupId;
  final String groupName;
  final String? createdBy;

  static Route<bool?> route({
    required String groupId,
    required String groupName,
    String? createdBy,
  }) {
    return MaterialPageRoute<bool?>(
      builder: (_) => GroupChatScreen(
        groupId: groupId,
        groupName: groupName,
        createdBy: createdBy,
      ),
    );
  }

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<GroupMessage> _messages = const [];
  GroupStreak? _streak;
  bool _loading = true;
  bool _sending = false;
  bool _deleting = false;
  bool _isOwner = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = AuthService().currentUser?.id;
    _isOwner = widget.createdBy != null && widget.createdBy == me;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = SquadGroupService();
      final messagesFuture = service.getGroupMessages(widget.groupId);
      final streakFuture = service.getGroupStreak(widget.groupId);
      final ownerFuture =
          _isOwner ? Future.value(true) : service.isGroupOwner(widget.groupId);
      final results = await Future.wait<Object?>([
        messagesFuture,
        streakFuture,
        ownerFuture,
      ]);
      if (!mounted) return;
      setState(() {
        _messages = results[0] as List<GroupMessage>;
        _streak = results[1] as GroupStreak?;
        _isOwner = results[2] as bool;
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

  Future<void> _confirmDelete() async {
    if (!_isOwner || _deleting) return;
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
    await _deleteGroup();
  }

  Future<void> _deleteGroup() async {
    setState(() => _deleting = true);
    try {
      await SquadGroupService().deleteSquadCircle(widget.groupId);
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
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await SquadGroupService().sendGroupMessage(
        groupId: widget.groupId,
        body: text,
      );
      if (!mounted) return;
      _input.clear();
      setState(() {
        _messages = [..._messages, msg];
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

  Future<void> _openGroupCamera() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(
          groupId: widget.groupId,
          groupName: widget.groupName,
          onDropped: () {
            Navigator.of(context).maybePop();
            _load();
          },
        ),
      ),
    );
    if (mounted) {
      final streak = await SquadGroupService().getGroupStreak(widget.groupId);
      if (mounted) setState(() => _streak = streak);
    }
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
        accent: AtmosphereAccent.tangerine,
        intensity: 0.55,
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Tall header + multi-line composer + keyboard → Column overflow.
              // Collapse the secondary feed CTA when vertical budget is tight.
              final compact = constraints.maxHeight < 480;

              return Column(
                children: [
                  _Header(
                    groupName: widget.groupName,
                    streak: _streak?.currentStreak ?? 0,
                    compact: compact,
                    onBack: _pop,
                    onWatchFeed: () {
                      FocusScope.of(context).unfocus();
                      Navigator.of(context).push(
                        GroupFeedScreen.route(
                          groupId: widget.groupId,
                          groupName: widget.groupName,
                        ),
                      );
                    },
                    showDelete: _isOwner && !_deleting,
                    onDelete: _confirmDelete,
                  ),
                  Expanded(
                    child: _loading || _deleting
                        ? const Center(
                            child:
                                NoolLottieView.loading(width: 64, height: 64),
                          )
                        : _error != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
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
                            : _messages.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(28),
                                      child: Text(
                                        context.s.groupChatEmpty,
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
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
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
                                      return _Bubble(
                                        message: msg,
                                        mine: mine,
                                      );
                                    },
                                  ),
                  ),
                  NoolChatComposer(
                    controller: _input,
                    hintText: context.s.groupChatHint,
                    sending: _sending,
                    onSend: _send,
                    trailing: [
                      BrutalPressable(
                        offset: const Offset(2, 2),
                        onTap: _openGroupCamera,
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NoolColors.tangerine,
                            border: Border.all(
                              color: NoolColors.ink,
                              width: 3,
                            ),
                          ),
                          child: Tooltip(
                            message: context.s.dropToGroupCta,
                            child: const Icon(
                              Icons.videocam,
                              color: NoolColors.ink,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.groupName,
    required this.streak,
    required this.onBack,
    required this.onWatchFeed,
    required this.showDelete,
    required this.onDelete,
    this.compact = false,
  });

  final String groupName;
  final int streak;
  final VoidCallback onBack;
  final VoidCallback onWatchFeed;
  final bool showDelete;
  final VoidCallback onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, compact ? 6 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                child: Text(
                  groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.syne(
                    color: NoolColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              if (compact) ...[
                const SizedBox(width: 6),
                BrutalPressable(
                  offset: const Offset(2, 2),
                  onTap: onWatchFeed,
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NoolColors.acid,
                      border: Border.all(color: NoolColors.ink, width: 3),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: NoolColors.ink,
                      size: 26,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: NoolColors.tangerine,
                  border: Border.all(color: NoolColors.ink, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: NoolColors.ink,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  '🔥 $streak',
                  style: GoogleFonts.syne(
                    color: NoolColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              if (showDelete) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: context.s.deleteKadroMenu,
                  color: NoolColors.night,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: const BorderSide(color: NoolColors.ink, width: 3),
                  ),
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(
                        context.s.deleteKadroMenu,
                        style: GoogleFonts.syne(
                          color: NoolColors.tangerine,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NoolColors.night,
                      border: Border.all(color: NoolColors.ink, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: NoolColors.ink,
                          offset: Offset(2, 2),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: NoolColors.acid,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            BrutalPressable(
              offset: const Offset(3, 3),
              onTap: onWatchFeed,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                decoration: BoxDecoration(
                  color: NoolColors.acid,
                  border: Border.all(color: NoolColors.ink, width: 3.5),
                ),
                child: Text(
                  context.s.watchGroupFeedCta,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.syne(
                    color: NoolColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final GroupMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final name = message.sender?.username ?? context.s.anonymousHandle;
    final handle = name.startsWith('@') ? name : '@$name';

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  handle,
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            Text(
              message.body,
              style: GoogleFonts.syne(
                color: mine ? NoolColors.ink : NoolColors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
