import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../icons/nool_icons.dart';
import '../models/squad_models.dart';
import '../models/user_profile.dart';
import '../models/vibe_post.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../widgets/nool_lottie.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';

/// Başka kullanıcının profili + Squad Up etkileşimi.
class OtherProfileScreen extends StatefulWidget {
  const OtherProfileScreen({
    super.key,
    required this.username,
    this.userId,
    this.deviceId,
  });

  final String username;
  final String? userId;
  final String? deviceId;

  /// Yorum / feed’den pürüzsüz geçiş.
  static Route<void> route({
    required String username,
    String? userId,
    String? deviceId,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => OtherProfileScreen(
        username: username,
        userId: userId,
        deviceId: deviceId,
      ),
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
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

class _OtherProfileScreenState extends State<OtherProfileScreen> {
  UserProfile? _profile;
  List<VibePost> _drops = const [];
  int _totalVibes = 0;
  SquadConnectionStatus _squadStatus = SquadConnectionStatus.notConnected;
  String? _pendingRequestId;

  bool _loading = true;
  bool _squadBusy = false;
  bool _messageBusy = false;
  bool _blockBusy = false;
  bool _iBlockedThem = false;
  bool _eitherBlocked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _displayName {
    final name = _profile?.username ?? widget.username;
    return name.startsWith('@') ? name : '@$name';
  }

  String? get _resolvedUserId => _profile?.id ?? widget.userId;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await ProfileService().fetchProfile(
        userId: widget.userId,
        username: widget.username,
      );

      // Kendi profilinse kişisel ekrana yönlendir.
      final myId = AuthService().currentUser?.id;
      if (profile != null && myId != null && profile.id == myId) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => const ProfileScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
        return;
      }

      final lookupName = profile?.username ?? widget.username;
      var drops = <VibePost>[];
      var vibes = 0;

      var status = SquadConnectionStatus.notConnected;
      String? requestId;
      var iBlocked = false;
      var eitherBlocked = false;
      final otherId = profile?.id ?? widget.userId;
      if (AuthService().isSignedIn && otherId != null) {
        eitherBlocked = await ProfileService().areUsersBlocked(otherId);
        iBlocked = await ProfileService().haveIBlocked(otherId);
        if (!eitherBlocked) {
          status = await ProfileService().getSquadStatus(otherId);
          if (status == SquadConnectionStatus.rejected) {
            status = SquadConnectionStatus.notConnected;
          }
          final edge = await ProfileService().findSquadWith(otherId);
          if (edge != null && edge.status == 'pending') {
            requestId = edge.id;
          }
        }
      }

      // Engelli çiftlerde drop içeriği yüklenmez / gösterilmez.
      if (!eitherBlocked) {
        drops = await ProfileService().getUploadedVideosForUser(
          username: lookupName,
          deviceId: widget.deviceId,
        );
        vibes = drops.fold<int>(0, (s, p) => s + p.vibeCount);
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _drops = drops;
        _totalVibes = vibes;
        _squadStatus = status;
        _pendingRequestId = requestId;
        _iBlockedThem = iBlocked;
        _eitherBlocked = eitherBlocked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onSquadTap() async {
    if (_squadBusy || _eitherBlocked) return;

    if (!AuthService().isSignedIn) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: NoolColors.night,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NoolColors.acid, width: 3),
          ),
          title: Text(
            'Önce giriş',
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Squad Up için hesabını güvenceye al.',
            style: GoogleFonts.syne(color: NoolColors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Sonra',
                style: GoogleFonts.syne(color: NoolColors.lavender),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Giriş Yap',
                style: GoogleFonts.syne(
                  color: NoolColors.acid,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
        );
        await _load();
      }
      return;
    }

    final otherId = _resolvedUserId;
    if (otherId == null) {
      _toast('Bu anon henüz kayıtlı profil bağlamamış.');
      return;
    }

    if (await ProfileService().areUsersBlocked(otherId)) {
      _toast('Bu kullanıcıyla etkileşim engellendi.');
      if (mounted) {
        setState(() {
          _eitherBlocked = true;
          _squadStatus = SquadConnectionStatus.notConnected;
        });
      }
      return;
    }

    setState(() => _squadBusy = true);
    try {
      switch (_squadStatus) {
        case SquadConnectionStatus.notConnected:
        case SquadConnectionStatus.rejected:
          await ProfileService().sendSquadRequest(otherId);
          if (!mounted) return;
          setState(() {
            _squadStatus = SquadConnectionStatus.pendingSent;
          });
          _toast('Squad isteği yolda.');
        case SquadConnectionStatus.pendingReceived:
          final id = _pendingRequestId;
          if (id == null) {
            final edge = await ProfileService().findSquadWith(otherId);
            if (edge == null) throw StateError('İstek bulunamadı.');
            await ProfileService().acceptSquadRequest(edge.id);
          } else {
            await ProfileService().acceptSquadRequest(id);
          }
          if (!mounted) return;
          setState(() => _squadStatus = SquadConnectionStatus.accepted);
          _toast('Squad kuruldu. Chaos together.');
        case SquadConnectionStatus.pendingSent:
        case SquadConnectionStatus.accepted:
          break;
      }
    } catch (e) {
      _toast('Squad işlemi başarısız: $e');
    } finally {
      if (mounted) setState(() => _squadBusy = false);
    }
  }

  Future<void> _onRejectTap() async {
    if (_squadBusy || _eitherBlocked) return;
    final otherId = _resolvedUserId;
    if (otherId == null) return;

    setState(() => _squadBusy = true);
    try {
      final id = _pendingRequestId;
      final edgeId = id ??
          (await ProfileService().findSquadWith(otherId))?.id;
      if (edgeId == null) throw StateError('İstek bulunamadı.');
      await ProfileService().rejectSquadRequest(edgeId);
      if (!mounted) return;
      setState(() {
        _squadStatus = SquadConnectionStatus.notConnected;
        _pendingRequestId = null;
      });
      _toast('İstek reddedildi.');
    } catch (e) {
      _toast('Reddetme başarısız: $e');
    } finally {
      if (mounted) setState(() => _squadBusy = false);
    }
  }

  Future<void> _onMessageTap() async {
    if (_messageBusy || _eitherBlocked) return;

    if (!AuthService().isSignedIn) {
      _toast('Mesaj için giriş yap.');
      return;
    }

    final otherId = _resolvedUserId;
    if (otherId == null) {
      _toast('Bu anon henüz kayıtlı profil bağlamamış.');
      return;
    }

    if (await ProfileService().areUsersBlocked(otherId)) {
      _toast('Bu kullanıcıyla mesajlaşma engellendi.');
      if (mounted) setState(() => _eitherBlocked = true);
      return;
    }

    setState(() => _messageBusy = true);
    try {
      final preview = await MessagingService().openDmWith(
        otherUserId: otherId,
        otherUsername: _displayName,
        otherAvatarUrl: _profile?.avatarUrl,
      );
      if (!mounted) return;
      await Navigator.of(context).push(ChatScreen.route(preview: preview));
    } catch (e) {
      _toast('Sohbet açılamadı: $e');
    } finally {
      if (mounted) setState(() => _messageBusy = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (_blockBusy) return;

    if (!AuthService().isSignedIn) {
      _toast('Engellemek için giriş yap.');
      return;
    }

    final otherId = _resolvedUserId;
    if (otherId == null) {
      _toast('Bu anon henüz kayıtlı profil bağlamamış.');
      return;
    }

    if (_iBlockedThem) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: NoolColors.night,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NoolColors.acid, width: 3),
          ),
          title: Text(
            'Engeli kaldır?',
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            '$_displayName ile tekrar etkileşim kurabilirsin.',
            style: GoogleFonts.syne(color: NoolColors.white, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Vazgeç',
                style: GoogleFonts.syne(color: NoolColors.lavender),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Kaldır',
                style: GoogleFonts.syne(
                  color: NoolColors.acid,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _blockBusy = true);
      try {
        await ProfileService().unblockUser(otherId);
        if (!mounted) return;
        _toast('Engel kaldırıldı.');
        await _load();
      } catch (e) {
        _toast('Engel kaldırılamadı: $e');
      } finally {
        if (mounted) setState(() => _blockBusy = false);
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NoolColors.night,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: NoolColors.tangerine, width: 3),
        ),
        title: Text(
          'Engelle?',
          style: GoogleFonts.syne(
            color: NoolColors.tangerine,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '$_displayName engellenecek. Drop’ları, yorumları ve mesajları '
          'gizlenir; squad / DM kesilir.',
          style: GoogleFonts.syne(color: NoolColors.white, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Vazgeç',
              style: GoogleFonts.syne(color: NoolColors.lavender),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ENGELLE',
              style: GoogleFonts.syne(
                color: NoolColors.tangerine,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _blockBusy = true);
    try {
      await ProfileService().blockUser(otherId);
      if (!mounted) return;
      _toast('Kullanıcı engellendi.');
      await _load();
    } catch (e) {
      _toast('Engellenemedi: $e');
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  void _openDrop(VibePost post) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => _OtherDropPlayer(post: post),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NoolColors.night,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NoolColors.night,
              Color.lerp(NoolColors.night, NoolColors.lavender, 0.16)!,
              NoolColors.night,
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: NoolColors.acid,
            backgroundColor: NoolColors.night,
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
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
                        const Spacer(),
                        Text(
                          'PROFIL',
                          style: GoogleFonts.syne(
                            color: NoolColors.lavender,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (!_loading && _error == null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: _blockBusy ? null : _toggleBlock,
                            tooltip: _iBlockedThem
                                ? 'Engeli kaldır'
                                : 'Engelle',
                            icon: _blockBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: NoolColors.tangerine,
                                    ),
                                  )
                                : NoolIcon(
                                    _iBlockedThem
                                        ? NoolIconData.close
                                        : NoolIconData.flag,
                                    color: NoolColors.tangerine,
                                    size: 20,
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: NoolLottieView.loading(width: 120, height: 120),
                      ),
                    ),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.syne(color: NoolColors.tangerine),
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(child: _buildStatusCard()),
                  if (_eitherBlocked)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                        child: Column(
                          children: [
                            Text(
                              _iBlockedThem
                                  ? 'Bu kullanıcıyı engelledin.'
                                  : 'Bu kullanıcıyla etkileşim engellenmiş.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.syne(
                                color: NoolColors.tangerine,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_iBlockedThem) ...[
                              const SizedBox(height: 12),
                              BrutalShadow(
                                offset: const Offset(4, 4),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed:
                                        _blockBusy ? null : _toggleBlock,
                                    child: Text(
                                      _blockBusy
                                          ? '...'
                                          : 'ENGELİ KALDIR',
                                      style: GoogleFonts.syne(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                      child: _SquadUpButton(
                        status: _squadStatus,
                        busy: _squadBusy,
                        onPressed: _onSquadTap,
                      ),
                    ),
                  ),
                  if (_squadStatus == SquadConnectionStatus.pendingReceived)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: BrutalShadow(
                          offset: const Offset(4, 4),
                          child: Material(
                            color: NoolColors.night,
                            child: InkWell(
                              onTap: _squadBusy ? null : _onRejectTap,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: NoolColors.tangerine,
                                    width: 3,
                                  ),
                                ),
                                child: Text(
                                  'Reddet',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.syne(
                                    color: NoolColors.tangerine,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_squadStatus == SquadConnectionStatus.accepted)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        child: BrutalShadow(
                          offset: const Offset(5, 5),
                          child: Material(
                            color: NoolColors.lavender,
                            child: InkWell(
                              onTap: _messageBusy ? null : _onMessageTap,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: NoolColors.ink,
                                    width: 3,
                                  ),
                                ),
                                child: _messageBusy
                                    ? const Center(
                                        child: NoolLottieView.loading(
                                          width: 28,
                                          height: 28,
                                          compact: true,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const NoolIcon(
                                            NoolIconData.send,
                                            color: NoolColors.ink,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Mesaj Gönder',
                                            style: GoogleFonts.syne(
                                              color: NoolColors.ink,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      child: TextButton(
                        onPressed: _blockBusy ? null : _toggleBlock,
                        child: Text(
                          'Engelle',
                          style: GoogleFonts.syne(
                            color: NoolColors.tangerine,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ],
                  if (!_eitherBlocked) ...[
                    // Engelli kullanıcıların drop'ları gizlenir.
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Text(
                          'DROPS',
                          style: GoogleFonts.syne(
                            color: NoolColors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    if (_drops.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Bu anon bugün henüz drop atmamış.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.syne(
                              color: NoolColors.lavender,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.72,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final post = _drops[index];
                              return _OtherDropTile(
                                post: post,
                                onTap: () => _openDrop(post),
                              );
                            },
                            childCount: _drops.length,
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final bio = _profile?.bio ?? '';
    final avatarUrl = _profile?.avatarUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: BrutalShadow(
        offset: const Offset(5, 5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: NoolColors.lavender.withOpacity(0.14),
                border: Border.all(color: NoolColors.ink, width: 3),
              ),
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: NoolColors.acid, width: 4),
                      color: NoolColors.night,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 224,
                            cacheHeight: 224,
                            errorBuilder: (_, __, ___) =>
                                const _OtherAvatarFallback(),
                          )
                        : const _OtherAvatarFallback(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _displayName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    bio.isEmpty ? 'Bio yok — mistik anon.' : bio,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: NoolColors.acid,
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'TOPLAM VIBE',
                          style: GoogleFonts.syne(
                            color: NoolColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$_totalVibes',
                          style: GoogleFonts.syne(
                            color: NoolColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SquadUpButton extends StatelessWidget {
  const _SquadUpButton({
    required this.status,
    required this.busy,
    required this.onPressed,
  });

  final SquadConnectionStatus status;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cfg = switch (status) {
      SquadConnectionStatus.notConnected ||
      SquadConnectionStatus.rejected =>
        (
          label: 'SQUAD UP! (Kadroya Kat)',
          bg: NoolColors.acid,
          fg: NoolColors.ink,
          enabled: true,
        ),
      SquadConnectionStatus.pendingSent => (
          label: 'İstek Gönderildi...',
          bg: NoolColors.lavender,
          fg: NoolColors.ink,
          enabled: false,
        ),
      SquadConnectionStatus.pendingReceived => (
          label: 'Kabul Et!',
          bg: NoolColors.tangerine,
          fg: NoolColors.ink,
          enabled: true,
        ),
      SquadConnectionStatus.accepted => (
          label: "SQUAD'DASINIZ!",
          bg: NoolColors.white,
          fg: NoolColors.ink,
          enabled: false,
        ),
    };

    final enabled = cfg.enabled && !busy;

    return BrutalShadow(
      offset: const Offset(5, 5),
      child: Material(
        color: cfg.bg,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: NoolColors.ink, width: 3),
            ),
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: const NoolLottieView.loading(
                        width: 28,
                        height: 28,
                        compact: true,
                      ),
                    ),
                  )
                : Text(
                    cfg.label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(
                      color: cfg.fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _OtherAvatarFallback extends StatelessWidget {
  const _OtherAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NoolColors.acid.withOpacity(0.18),
      child: const NoolIcon(
        NoolIconData.person,
        color: NoolColors.acid,
        size: 40,
      ),
    );
  }
}

class _OtherDropTile extends StatelessWidget {
  const _OtherDropTile({required this.post, required this.onTap});

  final VibePost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrutalShadow(
      offset: const Offset(3, 3),
      child: Material(
        color: Color.lerp(NoolColors.night, NoolColors.lavender, 0.14),
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: NoolColors.ink, width: 3),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Center(
                  child: NoolIcon(
                    NoolIconData.play,
                    color: NoolColors.acid,
                    size: 34,
                  ),
                ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: NoolColors.acid,
                      border: Border.all(color: NoolColors.ink, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: NoolColors.ink,
                          offset: Offset(2, 2),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Text(
                      '${post.vibeCount}',
                      style: GoogleFonts.syne(
                        color: NoolColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asit yeşili skeleton / shimmer yükleme.
class _ProfileSkeleton extends StatefulWidget {
  const _ProfileSkeleton();

  @override
  State<_ProfileSkeleton> createState() => _ProfileSkeletonState();
}

class _ProfileSkeletonState extends State<_ProfileSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final opacity = 0.25 + (_c.value * 0.45);
        Widget bone({
          required double height,
          double? width,
          BorderRadius? radius,
        }) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: NoolColors.acid.withOpacity(opacity),
              borderRadius: radius ?? BorderRadius.circular(2),
              border: Border.all(color: NoolColors.ink, width: 2),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            children: [
              bone(height: 96, width: 96, radius: BorderRadius.circular(48)),
              const SizedBox(height: 16),
              bone(height: 22, width: 160),
              const SizedBox(height: 10),
              bone(height: 14, width: double.infinity),
              const SizedBox(height: 8),
              bone(height: 14, width: 220),
              const SizedBox(height: 18),
              bone(height: 44, width: double.infinity),
              const SizedBox(height: 16),
              bone(height: 52, width: double.infinity),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: bone(height: 110)),
                  const SizedBox(width: 8),
                  Expanded(child: bone(height: 110)),
                  const SizedBox(width: 8),
                  Expanded(child: bone(height: 110)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OtherDropPlayer extends StatefulWidget {
  const _OtherDropPlayer({required this.post});

  final VibePost post;

  @override
  State<_OtherDropPlayer> createState() => _OtherDropPlayerState();
}

class _OtherDropPlayerState extends State<_OtherDropPlayer> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.post.videoUrl),
      );
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Video açılamadı.');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NoolColors.night,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio == 0
                      ? 9 / 16
                      : _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else if (_error != null)
              Center(
                child: Text(
                  _error!,
                  style: GoogleFonts.syne(color: NoolColors.tangerine),
                ),
              )
            else
              const Center(
                child: NoolLottieView.loading(width: 72, height: 72),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const NoolIcon(
                  NoolIconData.close,
                  color: NoolColors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
