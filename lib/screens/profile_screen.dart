import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../icons/nool_icons.dart';
import '../models/user_profile.dart';
import '../models/vibe_post.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../services/social_notification_service.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'inbox_screen.dart';
import 'splash_screen.dart';

/// Kişisel profil — avatar, bio, My Drops ızgarası, düzenle / sil.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.embedded = false,
  });

  /// LayoutManager sekmesi olarak gösteriliyorsa geri butonu gizlenir
  /// ve alt floating nav için padding eklenir.
  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  String _fallbackUsername = '@anon';
  List<VibePost> _drops = const [];
  bool _loading = true;
  String? _error;
  Timer? _ttlTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // 24 saat TTL: süresi dolan drop'lar pull olmadan da kaybolsun.
    _ttlTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _pruneExpiredDrops();
    });
  }

  @override
  void dispose() {
    _ttlTimer?.cancel();
    super.dispose();
  }

  void _pruneExpiredDrops() {
    if (!mounted || _drops.isEmpty) return;
    final fresh = SupabaseService.instance.filterFreshVideos(_drops);
    if (fresh.length != _drops.length) {
      setState(() => _drops = fresh);
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final localName = await OnboardingService.getUsername();
      final profile = await ProfileService().fetchMyProfile();
      final drops = await ProfileService().getMyUploadedVideos();
      if (!mounted) return;
      setState(() {
        _fallbackUsername = localName ?? AuthService().displayName ?? '@anon';
        _profile = profile;
        _drops = drops;
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

  String get _displayName {
    final fromProfile = _profile?.username;
    if (fromProfile != null && fromProfile.isNotEmpty) {
      return fromProfile.startsWith('@') ? fromProfile : '@$fromProfile';
    }
    return _fallbackUsername.startsWith('@')
        ? _fallbackUsername
        : '@$_fallbackUsername';
  }

  Future<void> _openEditSheet() async {
    if (!AuthService().isSignedIn) {
      _toast('Profil düzenlemek için giriş yap.');
      return;
    }

    final updated = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditProfileSheet(
        initialUsername: _profile?.username ?? _displayName,
        initialBio: _profile?.bio ?? '',
        initialAvatarUrl: _profile?.avatarUrl ?? AuthService().avatarUrl,
      ),
    );

    if (updated != null && mounted) {
      setState(() => _profile = updated);
      _toast('Profil güncellendi.');
    }
  }

  Future<void> _openBlockedSheet() async {
    if (!AuthService().isSignedIn) {
      _toast('Engellenenleri görmek için giriş yap.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BlockedUsersSheet(),
    );
  }

  Future<void> _confirmLogout() async {
    if (!AuthService().isSignedIn) {
      _toast('Zaten çıkış yapılmış.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NoolColors.night,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: NoolColors.acid, width: 3),
        ),
        title: Text(
          'Çıkış yap?',
          style: GoogleFonts.syne(
            color: NoolColors.acid,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        content: Text(
          'Oturumun kapanacak. Drop’ların kampüste kalır; tekrar girince '
          'profiline dönersin.',
          style: GoogleFonts.syne(
            color: NoolColors.white,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Vazgeç',
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          BrutalShadow(
            offset: const Offset(3, 3),
            child: Material(
              color: NoolColors.acid,
              child: InkWell(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: NoolColors.ink, width: 3),
                  ),
                  child: Text(
                    'ÇIKIŞ',
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await AuthService().signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, __, ___) => const SplashScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Çıkış yapılamadı: $e');
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (!AuthService().isSignedIn) {
      _toast('Silinecek hesap yok — önce giriş yap.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NoolColors.night,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: NoolColors.acid, width: 3),
        ),
        title: Text(
          'DİKKAT!',
          style: GoogleFonts.syne(
            color: NoolColors.acid,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        content: Text(
          'Bu işlem geri alınamaz, tüm videoların ve squad bağlantıların '
          'kampüsten silinecek!',
          style: GoogleFonts.syne(
            color: NoolColors.white,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Vazgeç',
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          BrutalShadow(
            offset: const Offset(3, 3),
            child: Material(
              color: NoolColors.tangerine,
              child: InkWell(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: NoolColors.ink, width: 3),
                  ),
                  child: Text(
                    'SİL',
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ProfileService().deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, __, ___) => const SplashScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Hesap silinemedi: $e');
    }
  }

  void _openDrop(VibePost post) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => _FullscreenDropPlayer(post: post),
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
      body: NoolAtmosphere(
        accent: AtmosphereAccent.lavender,
        intensity: 0.9,
        child: SafeArea(
          child: RefreshIndicator(
            color: NoolColors.acid,
            backgroundColor: NoolColors.night,
            onRefresh: _bootstrap,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      children: [
                        if (!widget.embedded)
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const NoolIcon(
                              NoolIconData.back,
                              color: NoolColors.white,
                              size: 22,
                            ),
                          )
                        else
                          const SizedBox(width: 8),
                        const NoolLogoMark(size: 28, border: true, shadow: false),
                        const SizedBox(width: 8),
                        Text(
                          'NOOL',
                          style: GoogleFonts.syne(
                            color: NoolColors.acid,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const Spacer(),
                        ValueListenableBuilder<int>(
                          valueListenable:
                              SocialNotificationService().unreadCount,
                          builder: (context, count, _) {
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  tooltip: 'Mesajlar',
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      InboxScreen.route(),
                                    );
                                  },
                                  icon: const NoolIcon(
                                    NoolIconData.send,
                                    color: NoolColors.white,
                                    size: 22,
                                  ),
                                ),
                                if (count > 0)
                                  Positioned(
                                    right: 6,
                                    top: 6,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: NoolColors.tangerine,
                                        border: Border.all(
                                          color: NoolColors.ink,
                                          width: 2,
                                        ),
                                      ),
                                      child: Text(
                                        count > 9 ? '9+' : '$count',
                                        style: GoogleFonts.syne(
                                          color: NoolColors.ink,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: BrutalShadow(
                            offset: const Offset(4, 4),
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _openEditSheet,
                                child: const Text('Profili Düzenle'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        BrutalShadow(
                          offset: const Offset(4, 4),
                          child: Material(
                            color: NoolColors.night,
                            child: InkWell(
                              onTap: _openBlockedSheet,
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: NoolColors.lavender,
                                    width: 3,
                                  ),
                                ),
                                child: Text(
                                  'Engel',
                                  style: GoogleFonts.syne(
                                    color: NoolColors.lavender,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        BrutalShadow(
                          offset: const Offset(4, 4),
                          child: Material(
                            color: NoolColors.night,
                            child: InkWell(
                              onTap: _confirmLogout,
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: NoolColors.white,
                                    width: 3,
                                  ),
                                ),
                                child: Text(
                                  'Çıkış',
                                  style: GoogleFonts.syne(
                                    color: NoolColors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        Text(
                          'MY DROPS',
                          style: GoogleFonts.syne(
                            color: NoolColors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· 24 saat',
                          style: GoogleFonts.syne(
                            color: NoolColors.lavender,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        if (!_loading && _error == null)
                          Text(
                            '${_drops.length}',
                            style: GoogleFonts.syne(
                              color: NoolColors.acid,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: NoolLottieView.loading(width: 96, height: 96),
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
                else if (_drops.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Henüz drop yok.\nKameradan kampüse bir kaos bırak.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
                          return _DropTile(
                            post: post,
                            onTap: () => _openDrop(post),
                          );
                        },
                        childCount: _drops.length,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      widget.embedded ? 120 : 40,
                    ),
                    child: TextButton(
                      onPressed: _confirmDeleteAccount,
                      child: Text(
                        'Hesabımı Kalıcı Olarak Sil',
                        style: GoogleFonts.syne(
                          color: NoolColors.tangerine,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
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

  Widget _buildHeader() {
    final bio = _profile?.bio ?? '';
    final avatarUrl = _profile?.avatarUrl ?? AuthService().avatarUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        children: [
          BrutalShadow(
            offset: const Offset(5, 5),
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NoolColors.night,
                border: Border.all(color: NoolColors.acid, width: 4),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 224,
                      cacheHeight: 224,
                      errorBuilder: (_, __, ___) => const _AvatarFallback(),
                    )
                  : const _AvatarFallback(),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            bio.isEmpty ? 'Bio yok — kampüste kim olduğunu yaz.' : bio,
            textAlign: TextAlign.center,
            style: GoogleFonts.syne(
              color: NoolColors.lavender,
              fontWeight: FontWeight.w500,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NoolColors.acid.withOpacity(0.2),
      child: const Center(
      child: NoolIcon(
        NoolIconData.person,
        color: NoolColors.acid,
        size: 48,
      ),
      ),
    );
  }
}

class _DropTile extends StatelessWidget {
  const _DropTile({required this.post, required this.onTap});

  final VibePost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrutalShadow(
      offset: const Offset(3, 3),
      child: Material(
        color: Color.lerp(NoolColors.night, NoolColors.lavender, 0.15),
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
                    size: 36,
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

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialUsername,
    required this.initialBio,
    this.initialAvatarUrl,
  });

  final String initialUsername;
  final String initialBio;
  final String? initialAvatarUrl;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _bioCtrl;
  bool _saving = false;
  String? _error;
  String? _pickedPath;
  String? _previewUrl;
  bool _removeAvatar = false;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(text: widget.initialUsername);
    _bioCtrl = TextEditingController(text: widget.initialBio);
    _previewUrl = widget.initialAvatarUrl;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  bool get _hasAvatarPreview =>
      _pickedPath != null ||
      (!_removeAvatar && _previewUrl != null && _previewUrl!.isNotEmpty);

  Future<void> _pickAvatar() async {
    try {
      final choice = await showModalBottomSheet<_AvatarPickAction>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: BrutalShadow(
              offset: const Offset(4, 4),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: NoolColors.night,
                  border: Border.all(color: NoolColors.ink, width: 3),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Profil fotoğrafı',
                      style: GoogleFonts.syne(
                        color: NoolColors.acid,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AvatarSourceTile(
                      label: 'Galeriden seç',
                      icon: NoolIconData.gallery,
                      onTap: () =>
                          Navigator.pop(ctx, _AvatarPickAction.gallery),
                    ),
                    const SizedBox(height: 8),
                    _AvatarSourceTile(
                      label: 'Kameradan çek',
                      icon: NoolIconData.camera,
                      onTap: () =>
                          Navigator.pop(ctx, _AvatarPickAction.camera),
                    ),
                    if (_hasAvatarPreview) ...[
                      const SizedBox(height: 8),
                      _AvatarSourceTile(
                        label: 'Fotoğrafı kaldır',
                        icon: NoolIconData.close,
                        danger: true,
                        onTap: () =>
                            Navigator.pop(ctx, _AvatarPickAction.remove),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (choice == null || !mounted) return;

      if (choice == _AvatarPickAction.remove) {
        setState(() {
          _pickedPath = null;
          _previewUrl = null;
          _removeAvatar = true;
          _error = null;
        });
        return;
      }

      final file = await ImagePicker().pickImage(
        source: choice == _AvatarPickAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() {
        _pickedPath = file.path;
        _previewUrl = null;
        _removeAvatar = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Fotoğraf seçilemedi: $e');
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ProfileService().updateProfile(
        username: _userCtrl.text,
        bio: _bioCtrl.text,
        avatarPath: _pickedPath,
        removeAvatar: _removeAvatar,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: NoolColors.night.withOpacity(0.82),
              border: Border.all(color: NoolColors.ink, width: 3),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      color: NoolColors.lavender,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Profili Düzenle',
                    style: GoogleFonts.syne(
                      color: NoolColors.acid,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: GestureDetector(
                      onTap: _saving ? null : _pickAvatar,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          BrutalShadow(
                            offset: const Offset(4, 4),
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: NoolColors.night,
                                border: Border.all(
                                  color: NoolColors.acid,
                                  width: 3,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _pickedPath != null
                                  ? Image.file(
                                      File(_pickedPath!),
                                      fit: BoxFit.cover,
                                    )
                                  : (!_removeAvatar &&
                                          _previewUrl != null &&
                                          _previewUrl!.isNotEmpty)
                                      ? Image.network(
                                          _previewUrl!,
                                          fit: BoxFit.cover,
                                          cacheWidth: 192,
                                          cacheHeight: 192,
                                          errorBuilder: (_, __, ___) =>
                                              const _AvatarFallback(),
                                        )
                                      : const _AvatarFallback(),
                            ),
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: NoolColors.acid,
                              border: Border.all(
                                color: NoolColors.ink,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: NoolColors.ink,
                                  offset: Offset(2, 2),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: const NoolIcon(
                              NoolIconData.gallery,
                              color: NoolColors.ink,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fotoğrafa dokun — galeri / kamera / kaldır',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GlassField(controller: _userCtrl, label: 'Kullanıcı adı'),
                  const SizedBox(height: 12),
                  _GlassField(
                    controller: _bioCtrl,
                    label: 'Bio (max 150)',
                    maxLines: 3,
                    maxLength: 150,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: GoogleFonts.syne(
                        color: NoolColors.tangerine,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  BrutalShadow(
                    offset: const Offset(4, 4),
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const NoolLottieView.loading(
                                width: 28,
                                height: 28,
                                compact: true,
                              )
                            : const Text('KAYDET'),
                      ),
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

enum _AvatarPickAction { gallery, camera, remove }

class _AvatarSourceTile extends StatelessWidget {
  const _AvatarSourceTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final NoolIconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? NoolColors.tangerine : NoolColors.white;
    return Material(
      color: NoolColors.lavender.withOpacity(0.12),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: danger ? NoolColors.tangerine : NoolColors.ink,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              NoolIcon(icon, color: fg, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.syne(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedUsersSheet extends StatefulWidget {
  const _BlockedUsersSheet();

  @override
  State<_BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends State<_BlockedUsersSheet> {
  List<UserProfile> _blocked = const [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ProfileService().listBlockedUsers();
      if (!mounted) return;
      setState(() {
        _blocked = list;
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

  Future<void> _unblock(UserProfile profile) async {
    setState(() => _busyId = profile.id);
    try {
      await ProfileService().unblockUser(profile.id);
      if (!mounted) return;
      setState(() {
        _blocked = _blocked.where((p) => p.id != profile.id).toList();
        _busyId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.acid,
          content: Text(
            'Engel kaldırıldı.',
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            'Kaldırılamadı: $e',
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.55;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: NoolColors.night.withOpacity(0.9),
            border: Border.all(color: NoolColors.ink, width: 3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  color: NoolColors.lavender,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Engellenenler',
                style: GoogleFonts.syne(
                  color: NoolColors.acid,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Engel kaldırınca tekrar squad isteği gidebilir.',
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(
                        child: NoolLottieView.loading(width: 72, height: 72),
                      )
                    : _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.syne(
                                color: NoolColors.tangerine,
                              ),
                            ),
                          )
                        : _blocked.isEmpty
                            ? Center(
                                child: Text(
                                  'Kimseyi engellemedin.',
                                  style: GoogleFonts.syne(
                                    color: NoolColors.lavender,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _blocked.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final p = _blocked[index];
                                  final name = p.username.startsWith('@')
                                      ? p.username
                                      : '@${p.username}';
                                  final busy = _busyId == p.id;
                                  return BrutalShadow(
                                    offset: const Offset(3, 3),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: NoolColors.lavender
                                            .withOpacity(0.12),
                                        border: Border.all(
                                          color: NoolColors.ink,
                                          width: 3,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: NoolColors.acid,
                                                width: 2,
                                              ),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: p.avatarUrl != null &&
                                                    p.avatarUrl!.isNotEmpty
                                                ? Image.network(
                                                    p.avatarUrl!,
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 88,
                                                    cacheHeight: 88,
                                                    errorBuilder: (_, __, ___) =>
                                                        const _AvatarFallback(),
                                                  )
                                                : const _AvatarFallback(),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: GoogleFonts.syne(
                                                color: NoolColors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed:
                                                busy ? null : () => _unblock(p),
                                            child: busy
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: NoolColors.acid,
                                                    ),
                                                  )
                                                : Text(
                                                    'Kaldır',
                                                    style: GoogleFonts.syne(
                                                      color: NoolColors.acid,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                          ),
                                        ],
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

class _GlassField extends StatelessWidget {
  const _GlassField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return BrutalShadow(
      offset: const Offset(3, 3),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        style: GoogleFonts.syne(
          color: NoolColors.white,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.syne(color: NoolColors.lavender),
          filled: true,
          fillColor: NoolColors.lavender.withOpacity(0.12),
          counterStyle: GoogleFonts.syne(color: NoolColors.lavender),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: NoolColors.ink, width: 3),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: NoolColors.acid, width: 3),
          ),
        ),
      ),
    );
  }
}

class _FullscreenDropPlayer extends StatefulWidget {
  const _FullscreenDropPlayer({required this.post});

  final VibePost post;

  @override
  State<_FullscreenDropPlayer> createState() => _FullscreenDropPlayerState();
}

class _FullscreenDropPlayerState extends State<_FullscreenDropPlayer> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.post.videoUrl),
    );
    _controller = c;
    try {
      await c.initialize();
      if (!mounted || _controller != c) {
        await c.dispose();
        if (_controller == c) _controller = null;
        return;
      }
      await c.setLooping(true);
      await c.play();
      if (!mounted || _controller != c) {
        await c.dispose();
        if (_controller == c) _controller = null;
        return;
      }
      setState(() {});
    } catch (e) {
      await c.dispose();
      if (_controller == c) _controller = null;
      if (!mounted) return;
      setState(() => _error = 'Video açılamadı.');
    }
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    c?.dispose();
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
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Text(
                '${widget.post.vibeCount} vibe · ${widget.post.caption}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
