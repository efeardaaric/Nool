import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../models/squad_models.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chrome.dart';
import 'direct_chat_screen.dart';
import 'other_profile_screen.dart';
import 'sign_in_screen.dart';

/// Kampüste insan ara — kullanıcı adı / bio.
class PeopleSearchScreen extends StatefulWidget {
  const PeopleSearchScreen({super.key});

  static Route<void> route() {
    return noolRoute<void>(page: const PeopleSearchScreen());
  }

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<UserProfile> _results = const [];
  final Map<String, SquadConnectionStatus> _statuses = {};
  final Set<String> _busyIds = {};
  bool _loading = false;
  String? _error;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _search(value);
    });
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q == _lastQuery && _results.isNotEmpty) return;
    _lastQuery = q;

    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
        _statuses.clear();
      });
      return;
    }

    if (!SupabaseService.instance.isReady) {
      setState(() {
        _error = 'Arama için bağlantı gerekli.';
        _loading = false;
        _results = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await ProfileService().searchProfiles(q);
      final statuses = <String, SquadConnectionStatus>{};
      if (AuthService().isSignedIn) {
        for (final p in list) {
          try {
            statuses[p.id] = await ProfileService().getSquadStatus(p.id);
          } catch (_) {
            statuses[p.id] = SquadConnectionStatus.notConnected;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _results = list;
        _statuses
          ..clear()
          ..addAll(statuses);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError(e, context.s);
        _results = const [];
      });
    }
  }

  Future<void> _openDm(UserProfile p) async {
    if (!AuthService().isSignedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      );
      return;
    }
    try {
      await DirectChatScreen.openWithUser(
        context,
        otherUserId: p.id,
        otherUsername: p.username,
        otherAvatarUrl: p.avatarUrl,
      );
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

  Future<void> _addFriend(UserProfile p) async {
    if (!AuthService().isSignedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      );
      return;
    }
    if (_busyIds.contains(p.id)) return;
    final status = _statuses[p.id] ?? SquadConnectionStatus.notConnected;
    if (status != SquadConnectionStatus.notConnected &&
        status != SquadConnectionStatus.rejected) {
      return;
    }

    setState(() => _busyIds.add(p.id));
    try {
      await ProfileService().sendSquadRequest(p.id);
      if (!mounted) return;
      setState(() {
        _statuses[p.id] = SquadConnectionStatus.pendingSent;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.acid,
          content: Text(
            context.s.friendPendingSent,
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
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
    } finally {
      if (mounted) setState(() => _busyIds.remove(p.id));
    }
  }

  String _friendLabel(SquadConnectionStatus status) {
    final s = context.s;
    switch (status) {
      case SquadConnectionStatus.notConnected:
      case SquadConnectionStatus.rejected:
        return s.friendAddCta;
      case SquadConnectionStatus.pendingSent:
        return s.friendPendingSent;
      case SquadConnectionStatus.pendingReceived:
        return s.friendPendingReceived;
      case SquadConnectionStatus.accepted:
        return s.friendAlready;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NoolColors.night,
      body: NoolAtmosphere(
        accent: AtmosphereAccent.acid,
        intensity: 0.75,
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
                      icon: const NoolIcon(
                        NoolIconData.back,
                        color: NoolColors.white,
                        size: 22,
                      ),
                    ),
                    Text(
                      'İnsan ara',
                      style: GoogleFonts.syne(
                        color: NoolColors.acid,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onQueryChanged,
                  onSubmitted: _search,
                  style: GoogleFonts.syne(
                    color: NoolColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: NoolColors.acid,
                  decoration: InputDecoration(
                    hintText: context.s.peopleSearchHint,
                    hintStyle: GoogleFonts.syne(color: NoolColors.lavender),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: NoolIcon(
                        NoolIconData.search,
                        color: NoolColors.acid,
                        size: 22,
                      ),
                    ),
                    filled: true,
                    fillColor: NoolColors.lavender.withValues(alpha: 0.12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(2),
                      borderSide: const BorderSide(
                        color: NoolColors.lavender,
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
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: NoolColors.acid),
                      )
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _error!,
                              style: GoogleFonts.syne(
                                color: NoolColors.tangerine,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : _lastQuery.isNotEmpty && _results.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Kimse bulunamadı.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.syne(
                                    color: NoolColors.lavender,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
                                itemCount: _results.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final p = _results[i];
                                  final name = p.username.startsWith('@')
                                      ? p.username
                                      : '@${p.username}';
                                  return Material(
                                    color: NoolColors.night,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          OtherProfileScreen.route(
                                            username: name,
                                            userId: p.id,
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 12, 12, 12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: NoolColors.lavender,
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
                                          children: [
                                            NoolAvatar(
                                              size: 48,
                                              borderWidth: 2.5,
                                              imageUrl: p.avatarUrl,
                                              showShadow: true,
                                              fallbackInitial: name,
                                              backgroundColor: NoolColors.acid,
                                              fallbackIconSize: 22,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: GoogleFonts.syne(
                                                      color: NoolColors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  if (p.bio.isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      p.bio,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: GoogleFonts.syne(
                                                        color:
                                                            NoolColors.lavender,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Builder(
                                              builder: (context) {
                                                final status =
                                                    _statuses[p.id] ??
                                                        SquadConnectionStatus
                                                            .notConnected;
                                                final canAdd = status ==
                                                        SquadConnectionStatus
                                                            .notConnected ||
                                                    status ==
                                                        SquadConnectionStatus
                                                            .rejected;
                                                return BrutalPressable(
                                                  offset: const Offset(2, 2),
                                                  onTap: canAdd
                                                      ? () => _addFriend(p)
                                                      : () {
                                                          Navigator.of(context)
                                                              .push(
                                                            OtherProfileScreen
                                                                .route(
                                                              username: name,
                                                              userId: p.id,
                                                            ),
                                                          );
                                                        },
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: canAdd
                                                          ? NoolColors.acid
                                                          : NoolColors.lavender,
                                                      border: Border.all(
                                                        color: NoolColors.ink,
                                                        width: 2.5,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _busyIds.contains(p.id)
                                                          ? '…'
                                                          : _friendLabel(
                                                              status),
                                                      style: GoogleFonts.syne(
                                                        color: NoolColors.ink,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 6),
                                            BrutalPressable(
                                              offset: const Offset(2, 2),
                                              onTap: () => _openDm(p),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: NoolColors.tangerine,
                                                  border: Border.all(
                                                    color: NoolColors.ink,
                                                    width: 2.5,
                                                  ),
                                                ),
                                                child: Text(
                                                  context.s.dmMessageCta,
                                                  style: GoogleFonts.syne(
                                                    color: NoolColors.ink,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12,
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
            ],
          ),
        ),
      ),
    );
  }
}
