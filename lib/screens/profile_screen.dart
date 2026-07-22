import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../icons/nool_icons.dart';
import '../models/user_profile.dart';
import '../models/vibe_post.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
      ),
    );

    if (updated != null && mounted) {
      setState(() => _profile = updated);
      _toast('Profil güncellendi.');
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                          const SizedBox(width: 12),
                        const Spacer(),
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
                              onTap: _confirmDeleteAccount,
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: NoolColors.tangerine,
                                    width: 3,
                                  ),
                                ),
                                child: Text(
                                  'Sil',
                                  style: GoogleFonts.syne(
                                    color: NoolColors.tangerine,
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
                    child: Text(
                      'MY DROPS',
                      style: GoogleFonts.syne(
                        color: NoolColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 0.6,
                      ),
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
  });

  final String initialUsername;
  final String initialBio;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _bioCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(text: widget.initialUsername);
    _bioCtrl = TextEditingController(text: widget.initialBio);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
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
    } catch (e) {
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
