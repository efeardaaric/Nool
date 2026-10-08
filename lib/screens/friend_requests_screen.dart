import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../models/squad_models.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_lottie.dart';
import 'other_profile_screen.dart';

/// Incoming + outgoing friend (squad) requests inbox.
class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  static Route<void> route() {
    return noolRoute<void>(page: const FriendRequestsScreen());
  }

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  List<SquadEdge> _incoming = const [];
  List<SquadEdge> _outgoing = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthService().isSignedIn) {
      setState(() {
        _loading = false;
        _incoming = const [];
        _outgoing = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final pending = await ProfileService().getPendingFriendRequests();
      if (!mounted) return;
      setState(() {
        _incoming = pending.incoming;
        _outgoing = pending.outgoing;
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

  Future<void> _accept(SquadEdge edge) async {
    if (_busy.contains(edge.id)) return;
    setState(() => _busy.add(edge.id));
    try {
      await ProfileService().acceptSquadRequest(edge.id);
      if (!mounted) return;
      _toast(context.s.friendAcceptedToast);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(userFacingError(e, context.s));
    } finally {
      if (mounted) setState(() => _busy.remove(edge.id));
    }
  }

  Future<void> _reject(SquadEdge edge) async {
    if (_busy.contains(edge.id)) return;
    setState(() => _busy.add(edge.id));
    try {
      await ProfileService().rejectSquadRequest(edge.id);
      if (!mounted) return;
      _toast(context.s.friendRejectedToast);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(userFacingError(e, context.s));
    } finally {
      if (mounted) setState(() => _busy.remove(edge.id));
    }
  }

  Future<void> _cancel(SquadEdge edge) async {
    if (_busy.contains(edge.id)) return;
    setState(() => _busy.add(edge.id));
    try {
      await ProfileService().cancelSquadRequest(edge.id);
      if (!mounted) return;
      _toast(context.s.friendCancelledToast);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(userFacingError(e, context.s));
    } finally {
      if (mounted) setState(() => _busy.remove(edge.id));
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

  void _openProfile(SquadEdge edge) {
    final p = edge.otherProfile;
    final name = p?.username ?? context.s.anonymousUser;
    Navigator.of(context).push(
      OtherProfileScreen.route(
        username: name,
        userId: p?.id ??
            (edge.senderId == AuthService().currentUser?.id
                ? edge.receiverId
                : edge.senderId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.tangerine,
        intensity: 0.8,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
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
                        s.friendRequestsTitle,
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ],
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
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + bottom),
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  _error!,
                                  style: GoogleFonts.syne(
                                    color: NoolColors.tangerine,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Text(
                              s.friendIncomingSection,
                              style: GoogleFonts.syne(
                                color: NoolColors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_incoming.isEmpty)
                              _EmptyHint(text: s.friendIncomingEmpty)
                            else
                              for (final edge in _incoming) ...[
                                _RequestTile(
                                  edge: edge,
                                  busy: _busy.contains(edge.id),
                                  onTap: () => _openProfile(edge),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _MiniCta(
                                        label: s.friendReject,
                                        bg: NoolColors.lavender,
                                        onTap: () => _reject(edge),
                                      ),
                                      const SizedBox(width: 8),
                                      _MiniCta(
                                        label: s.friendAccept,
                                        bg: NoolColors.acid,
                                        onTap: () => _accept(edge),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                            const SizedBox(height: 22),
                            Text(
                              s.friendOutgoingSection,
                              style: GoogleFonts.syne(
                                color: NoolColors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_outgoing.isEmpty)
                              _EmptyHint(text: s.friendOutgoingEmpty)
                            else
                              for (final edge in _outgoing) ...[
                                _RequestTile(
                                  edge: edge,
                                  busy: _busy.contains(edge.id),
                                  onTap: () => _openProfile(edge),
                                  trailing: _MiniCta(
                                    label: s.friendCancel,
                                    bg: NoolColors.tangerine,
                                    onTap: () => _cancel(edge),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                          ],
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: NoolColors.lavender, width: 3),
      ),
      child: Text(
        text,
        style: GoogleFonts.syne(
          color: NoolColors.lavender,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.edge,
    required this.busy,
    required this.onTap,
    required this.trailing,
  });

  final SquadEdge edge;
  final bool busy;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final nameRaw = edge.otherProfile?.username ?? context.s.anonymousUser;
    final name = nameRaw.startsWith('@') ? nameRaw : '@$nameRaw';

    return Material(
      color: NoolColors.night,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
          child: Row(
            children: [
              NoolAvatar(
                size: 48,
                borderWidth: 2.5,
                imageUrl: edge.otherProfile?.avatarUrl,
                fallbackInitial: name,
                backgroundColor: NoolColors.acid,
                showShadow: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.syne(
                    color: NoolColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: NoolColors.acid,
                  ),
                )
              else
                trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniCta extends StatelessWidget {
  const _MiniCta({
    required this.label,
    required this.bg,
    required this.onTap,
  });

  final String label;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrutalPressable(
      offset: const Offset(2, 2),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: NoolColors.ink, width: 2.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.syne(
            color: NoolColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
