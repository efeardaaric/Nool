import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../models/user_profile.dart';
import '../models/vibe_post.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_avatar.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import '../widgets/nool_notification_entry.dart';
import 'settings_screen.dart';
import 'splash_screen.dart';

/// Kişisel profil — avatar, bio, My Drops, düzenle / çıkış / ayarlar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  String _fallbackUsername = AppStrings.fromSettings().anonymousHandle;
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
        _fallbackUsername = localName ??
            AuthService().displayName ??
            AppStrings.fromSettings().anonymousHandle;
        _profile = profile;
        _drops = drops;
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
      _toast(context.s.editProfileNeedSignIn);
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
      _toast(context.s.profileUpdated);
    }
  }

  Future<void> _signOut() async {
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
      _toast(userFacingError(e, context.s));
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(SettingsScreen.route());
    if (mounted) await _bootstrap();
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

  Future<void> _manageDrop(VibePost post) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sheet = AppStrings.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: NoolColors.night,
              border: Border.all(color: NoolColors.acid, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: NoolColors.ink,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  sheet.dropManageTitle,
                  style: GoogleFonts.syne(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'edit'),
                  child: Text(
                    sheet.dropEditCaption,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  child: Text(
                    sheet.dropDelete,
                    style: GoogleFonts.syne(
                      color: NoolColors.tangerine,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;

    if (action == 'delete') {
      final ok = await _confirmDeleteDrop();
      if (ok != true || !mounted) return;
      try {
        await ProfileService().deleteMyVideo(post);
        if (!mounted) return;
        setState(() => _drops = _drops.where((d) => d.id != post.id).toList());
        _toast(context.s.dropDeletedToast);
      } catch (e) {
        _toast(
          '${context.s.dropDeleteFailed}: ${userFacingError(e, context.s)}',
        );
      }
      return;
    }

    if (action == 'edit') {
      final ctrl = TextEditingController(text: post.caption);
      final next = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final d = AppStrings.of(ctx);
          return AlertDialog(
            backgroundColor: NoolColors.night,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: NoolColors.acid, width: 3),
            ),
            title: Text(
              d.dropCaptionTitle,
              style: GoogleFonts.syne(
                color: NoolColors.acid,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: TextField(
              controller: ctrl,
              maxLines: 3,
              style: GoogleFonts.syne(color: NoolColors.white),
              decoration: const InputDecoration(
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: NoolColors.lavender, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: NoolColors.acid, width: 2),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  d.cancel,
                  style: GoogleFonts.syne(color: NoolColors.lavender),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(
                  d.save,
                  style: GoogleFonts.syne(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      );
      ctrl.dispose();
      if (next == null || !mounted) return;
      try {
        await ProfileService().updateMyVideoCaption(
          videoId: post.id,
          caption: next,
        );
        if (!mounted) return;
        setState(() {
          _drops = _drops
              .map((d) => d.id == post.id ? d.copyWith(caption: next) : d)
              .toList();
        });
        _toast(context.s.dropCaptionUpdated);
      } catch (e) {
        _toast(
          '${context.s.dropCaptionFailed}: ${userFacingError(e, context.s)}',
        );
      }
    }
  }

  Future<bool?> _confirmDeleteDrop() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final s = AppStrings.of(ctx);
        return AlertDialog(
          backgroundColor: NoolColors.night,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NoolColors.acid, width: 3),
          ),
          title: Text(
            s.dropDeleteConfirmTitle,
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          content: Text(
            s.dropDeleteConfirmBody,
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
                    s.deleteConfirm,
                    style: GoogleFonts.syne(
                      color: NoolColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NoolColors.acid,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          widget.embedded ? 110 : 24,
        ),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
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
                          const SizedBox(width: 4),
                        const NoolLogoMark(
                            size: 28, border: true, shadow: false),
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
                        const NoolNotificationEntry(showRequests: true),
                        IconButton(
                          onPressed: _openSettings,
                          tooltip: context.s.settings,
                          icon: const Icon(
                            Icons.settings_rounded,
                            color: NoolColors.white,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            label: context.s.editProfile,
                            filled: true,
                            onTap: _openEditSheet,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButton(
                            label: context.s.signOut,
                            filled: false,
                            onTap: _signOut,
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
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: NoolColors.acid,
                            border: Border.all(color: NoolColors.ink, width: 2),
                          ),
                          child: Text(
                            '${_drops.length}',
                            style: GoogleFonts.syne(
                              color: NoolColors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
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
                        context.s.noDropsYet,
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
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      widget.embedded ? 120 : 40,
                    ),
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
                            onLongPress: () => _manageDrop(post),
                            onManage: () => _manageDrop(post),
                          );
                        },
                        childCount: _drops.length,
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
          NoolAvatar(
            size: 112,
            borderWidth: 4,
            imageUrl: avatarUrl,
            showShadow: true,
            fallbackIconSize: 48,
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
            bio.isEmpty ? context.s.noBio : bio,
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // filled = Profili Düzenle: morumsu (lavender) + beyaz yazı + kalın siyah kenar.
    // outline = Sign out: night zemin + beyaz yazı.
    // Material 3 surfaceTint kapalı — asit/lavender siyahlaşmasın.
    final bg = filled ? NoolColors.lavender : NoolColors.night;
    const fg = NoolColors.white;

    return Material(
      color: bg,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: NoolColors.white.withValues(alpha: 0.12),
        highlightColor: NoolColors.white.withValues(alpha: 0.06),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: NoolColors.ink, width: 3.5),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: GoogleFonts.syne(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropTile extends StatelessWidget {
  const _DropTile({
    required this.post,
    required this.onTap,
    this.onLongPress,
    this.onManage,
  });

  final VibePost post;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.lerp(NoolColors.night, NoolColors.lavender, 0.15),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: NoolColors.lavender, width: 3),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _DropVideoThumb(url: post.videoUrl),
              const Center(
                child: NoolIcon(
                  NoolIconData.play,
                  color: NoolColors.acid,
                  size: 28,
                ),
              ),
              if (onManage != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: NoolColors.night,
                    child: InkWell(
                      onTap: onManage,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: NoolColors.ink, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: NoolColors.ink,
                              offset: Offset(2, 2),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.more_horiz,
                          color: NoolColors.acid,
                          size: 18,
                        ),
                      ),
                    ),
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
    );
  }
}

/// Grid için video ilk karesi.
class _DropVideoThumb extends StatefulWidget {
  const _DropVideoThumb({required this.url});

  final String url;

  @override
  State<_DropVideoThumb> createState() => _DropVideoThumbState();
}

class _DropVideoThumbState extends State<_DropVideoThumb> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.url.isEmpty) return;
    try {
      final c = VideoPlayerController.networkUrl(
          await SupabaseService.instance.playableVideoUri(widget.url));
      await c.initialize();
      await c.setVolume(0);
      await c.pause();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _c == null || !_c!.value.isInitialized) {
      return ColoredBox(
        color: NoolColors.lavender.withValues(alpha: 0.15),
        child: const Center(
          child: NoolLottieView.loading(width: 36, height: 36, compact: true),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _c!.value.size.width,
        height: _c!.value.size.height,
        child: VideoPlayer(_c!),
      ),
    );
  }
}

enum _AvatarPhotoAction { gallery, camera, remove }

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
  final _picker = ImagePicker();

  bool _saving = false;
  String? _error;
  File? _localAvatar;
  bool _removeAvatar = false;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(
      text: widget.initialUsername.replaceFirst(RegExp(r'^@'), ''),
    );
    _bioCtrl = TextEditingController(text: widget.initialBio);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      // requestFullMetadata: false → iOS PHPicker izin istemeden açılır
      // (NSPhotoLibraryUsageDescription yine Info.plist'te durur).
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (xfile == null) return;

      // iOS PHPicker bazen path vermez / public.jpeg fail eder —
      // bytes'ı temp dosyaya yaz.
      final bytes = await xfile.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('Seçilen görsel boş.');
      }
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/nool_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      setState(() {
        _localAvatar = out;
        _removeAvatar = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = source == ImageSource.gallery
            ? 'Galeri açılamadı. Ayarlar → Nool → Fotoğraflar iznini kontrol et.'
            : 'Kamera açılamadı. Ayarlar → Nool → Kamera iznini kontrol et.';
      });
      debugPrint('Avatar pick PlatformException: ${e.code} ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Fotoğraf seçilemedi. Galeri veya kamerayı tekrar dene.';
      });
      debugPrint('Avatar pick error: $e');
    }
  }

  Future<void> _showPhotoSheet() async {
    // Seçimi sheet sonucu olarak al — pop + hemen pickImage iOS'ta
    // "already presenting" ile PHPicker'ı kırar.
    final action = await showModalBottomSheet<_AvatarPhotoAction>(
      context: context,
      backgroundColor: NoolColors.night,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: NoolColors.ink, width: 3),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Galeriden seç',
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.pop(ctx, _AvatarPhotoAction.gallery),
            ),
            ListTile(
              title: Text(
                'Kameradan çek',
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.pop(ctx, _AvatarPhotoAction.camera),
            ),
            ListTile(
              title: Text(
                'Fotoğrafı kaldır',
                style: GoogleFonts.syne(
                  color: NoolColors.tangerine,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.pop(ctx, _AvatarPhotoAction.remove),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    // Sheet dismiss animasyonu bitsin; sonra native picker present edilsin.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    switch (action) {
      case _AvatarPhotoAction.gallery:
        await _pick(ImageSource.gallery);
      case _AvatarPhotoAction.camera:
        await _pick(ImageSource.camera);
      case _AvatarPhotoAction.remove:
        setState(() {
          _localAvatar = null;
          _removeAvatar = true;
        });
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
        avatarPath: _localAvatar?.path,
        clearAvatar: _removeAvatar,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userFacingError(e, context.s);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    final previewUrl = _removeAvatar ? null : widget.initialAvatarUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: NoolColors.night.withValues(alpha: 0.96),
                  border: Border.all(color: NoolColors.acid, width: 3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
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
                            Center(
                              child: GestureDetector(
                                onTap: _showPhotoSheet,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    NoolAvatar(
                                      size: 96,
                                      borderWidth: 3.5,
                                      imageUrl: previewUrl,
                                      localFile: _localAvatar,
                                      showShadow: true,
                                      fallbackIconSize: 40,
                                    ),
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: NoolColors.acid,
                                          border: Border.all(
                                            color: NoolColors.ink,
                                            width: 2.5,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.photo_camera_outlined,
                                          size: 16,
                                          color: NoolColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.s.tapPhotoHint,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.syne(
                                color: NoolColors.lavender,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _GlassField(
                              controller: _userCtrl,
                              label: context.s.usernameLabel,
                            ),
                            const SizedBox(height: 12),
                            _GlassField(
                              controller: _bioCtrl,
                              label: context.s.bioLabel,
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
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        16 + (bottomInset > 0 ? 0 : safeBottom),
                      ),
                      child: Material(
                        color: NoolColors.acid,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        child: InkWell(
                          onTap: _saving ? null : _save,
                          splashColor: NoolColors.ink.withValues(alpha: 0.12),
                          highlightColor:
                              NoolColors.ink.withValues(alpha: 0.06),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 54),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: NoolColors.acid,
                              border: Border.all(
                                color: NoolColors.ink,
                                width: 3.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: NoolColors.ink,
                                  offset: Offset(4, 4),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: _saving
                                ? const NoolLottieView.loading(
                                    width: 28,
                                    height: 28,
                                    compact: true,
                                  )
                                : Text(
                                    'KAYDET',
                                    style: GoogleFonts.syne(
                                      // Asit zemin → night metin (yüksek kontrast).
                                      // M3 tint asidi karartırsa yine okunur kalsın diye w800.
                                      color: NoolColors.night,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      letterSpacing: 0.4,
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
    return TextField(
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
        fillColor: NoolColors.lavender.withValues(alpha: 0.12),
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
        await SupabaseService.instance.playableVideoUri(widget.post.videoUrl),
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
