import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../models/squad_models.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/squad_group_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';
import 'group_chat_screen.dart';

/// Neo-brutal kadro (squad circle) oluşturma ekranı.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const CreateGroupScreen(),
    );
  }

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _selected = <String>{};

  List<SquadEdge> _friends = const [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    if (!AuthService().isSignedIn) {
      setState(() {
        _loading = false;
        _friends = const [];
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final friends = await ProfileService().getMySquadList();
      if (!mounted) return;
      setState(() {
        _friends = friends;
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

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _creating) return;

    setState(() => _creating = true);
    try {
      final me = AuthService().currentUser?.id;
      final memberIds = <String>{
        if (me != null) me,
        ..._selected,
      }.toList();

      final group = await SquadGroupService().createSquadCircle(
        groupName: name,
        memberUserIds: memberIds,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        GroupChatScreen.route(
          groupId: group.id,
          groupName: group.name,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
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

  void _toggle(String userId) {
    setState(() {
      if (_selected.contains(userId)) {
        _selected.remove(userId);
      } else {
        _selected.add(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _nameCtrl.text.trim().isNotEmpty && !_creating;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.acid,
        intensity: 0.7,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: NoolColors.acid,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        context.s.createCircleTitle,
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: NoolLottieView.loading(width: 72, height: 72),
                      )
                    : _error != null
                        ? Center(
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
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                            children: [
                              ClipRRect(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 12,
                                    sigmaY: 12,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: NoolColors.lavender
                                          .withValues(alpha: 0.14),
                                      border: Border.all(
                                        color: NoolColors.ink,
                                        width: 3.5,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: NoolColors.ink,
                                          offset: Offset(3, 3),
                                          blurRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: _nameCtrl,
                                      onChanged: (_) => setState(() {}),
                                      style: GoogleFonts.syne(
                                        color: NoolColors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                      cursorColor: NoolColors.acid,
                                      decoration: InputDecoration(
                                        hintText:
                                            context.s.createCircleNameHint,
                                        hintStyle: GoogleFonts.syne(
                                          color: NoolColors.lavender,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                context.s.createCirclePickMembers,
                                style: GoogleFonts.syne(
                                  color: NoolColors.lavender,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_friends.isEmpty)
                                _EmptyFriendsState()
                              else
                                for (final edge in _friends) ...[
                                  _FriendSelectTile(
                                    edge: edge,
                                    selected: _selected.contains(
                                      edge.otherProfile?.id ?? '',
                                    ),
                                    onToggle: edge.otherProfile == null
                                        ? null
                                        : () => _toggle(edge.otherProfile!.id),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                            ],
                          ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  MediaQuery.paddingOf(context).bottom + 16,
                ),
                child: BrutalPressable(
                  offset: const Offset(4, 4),
                  enabled: canSubmit,
                  onTap: canSubmit ? _create : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: canSubmit
                          ? NoolColors.acid
                          : NoolColors.lavender.withValues(alpha: 0.35),
                      border: Border.all(color: NoolColors.ink, width: 3.5),
                    ),
                    child: _creating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: NoolColors.ink,
                            ),
                          )
                        : Text(
                            context.s.createCircleCta,
                            style: GoogleFonts.syne(
                              color: NoolColors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
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

class _EmptyFriendsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NoolColors.lavender.withValues(alpha: 0.12),
        border: Border.all(color: NoolColors.ink, width: 3.5),
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
          Text(
            context.s.noSquadYet,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.s.noSquadHint,
            style: GoogleFonts.syne(
              color: NoolColors.lavender,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendSelectTile extends StatelessWidget {
  const _FriendSelectTile({
    required this.edge,
    required this.selected,
    required this.onToggle,
  });

  final SquadEdge edge;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final other = edge.otherProfile;
    final name = other?.username ?? context.s.anonymousHandle;
    final avatar = other?.avatarUrl;
    final enabled = onToggle != null;

    return BrutalPressable(
      offset: const Offset(3, 3),
      enabled: enabled,
      onTap: onToggle ?? () {},
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: selected
              ? NoolColors.acid.withValues(alpha: 0.18)
              : NoolColors.lavender.withValues(alpha: 0.12),
          border: Border.all(
            color: selected ? NoolColors.acid : NoolColors.ink,
            width: 3,
          ),
        ),
        child: Row(
          children: [
            NoolAvatar(
              size: 44,
              borderWidth: 2.5,
              imageUrl: avatar,
              borderColor: selected ? NoolColors.acid : NoolColors.lavender,
              fallbackIconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name.startsWith('@') ? name : '@$name',
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? NoolColors.acid : Colors.transparent,
                border: Border.all(
                  color: selected ? NoolColors.ink : NoolColors.lavender,
                  width: 2.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 18, color: NoolColors.ink)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
