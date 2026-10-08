import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../icons/nool_icons.dart';
import '../l10n/app_strings.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/onboarding_service.dart';
import '../services/profile_service.dart';
import '../services/squad_group_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/claim_student_email_sheet.dart';
import '../widgets/nool_lottie.dart';

/// Kamera — sınırsız süre kayıt, önizleme, Supabase drop.
///
/// [groupId] verilirse campus yerine kadro `group-drops` yüklemesi yapılır.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.isActive = true,
    this.onExit,
    this.onDropped,
    this.groupId,
    this.groupName,
  });

  final bool isActive;
  final VoidCallback? onExit;
  final VoidCallback? onDropped;

  /// Kadro drop modu — doluysa `SquadGroupService.dropVideoToGroup`.
  final String? groupId;

  /// Grup adı — upload UI’da hedef etiketi için.
  final String? groupName;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  bool _initializing = true;
  String? _error;
  bool _flashOn = false;
  bool _recording = false;
  bool _busy = false;

  String? _recordedPath;
  VideoPlayerController? _playback;

  bool _dropping = false;
  final _captionController = TextEditingController();

  /// `true` → visibility=campus (aynı domain); `false` → public / Near You.
  bool _dropToCampus = false;
  bool _hasCampusAccess = false;
  String? _campusDomain;

  Timer? _recordTimer;
  int _elapsedSeconds = 0;

  /// Optical / digital zoom for the active camera (Instagram-style drag).
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _zoomAtGestureStart = 1.0;
  bool _zoomUiVisible = false;
  bool _zoomGestureActive = false;
  Timer? _zoomLabelTimer;

  static const _groupMaxSeconds = 15;

  bool get _isGroupDrop {
    final id = widget.groupId;
    return id != null && id.isNotEmpty;
  }

  String get _groupLabel {
    final name = widget.groupName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Kadro';
  }

  bool get _isFront {
    if (_cameras.isEmpty || _cameraIndex >= _cameras.length) return true;
    return _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCampusAccess());
    if (widget.isActive) {
      unawaited(_boot());
    } else {
      _initializing = false;
    }
  }

  Future<void> _refreshCampusAccess() async {
    if (!SupabaseService.instance.isReady || !AuthService().isSignedIn) {
      if (!mounted) return;
      setState(() {
        _hasCampusAccess = false;
        _campusDomain = null;
        _dropToCampus = false;
      });
      return;
    }
    try {
      final profile = await ProfileService().fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _hasCampusAccess = profile?.hasCampusAccess ?? false;
        _campusDomain = profile?.campusDomain;
        if (!_hasCampusAccess) _dropToCampus = false;
      });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant CameraScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_boot());
    } else if (!widget.isActive && oldWidget.isActive) {
      unawaited(_tearDownCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _zoomLabelTimer?.cancel();
    _captionController.dispose();
    _playback?.dispose();
    final cam = _camera;
    _camera = null;
    unawaited(cam?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _startElapsedTimer() {
    _recordTimer?.cancel();
    _elapsedSeconds = 0;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording) return;
      final next = _elapsedSeconds + 1;
      setState(() => _elapsedSeconds = next);
      // Kadro drop: 15 sn soft cap.
      if (_isGroupDrop && next >= _groupMaxSeconds) {
        unawaited(_stopRecording());
      }
    });
  }

  void _stopElapsedTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  Future<void> _tearDownCamera() async {
    if (_recording) {
      try {
        await _camera?.stopVideoRecording();
      } catch (_) {}
    }
    _stopElapsedTimer();
    _elapsedSeconds = 0;
    await _playback?.dispose();
    _playback = null;
    final cam = _camera;
    _camera = null;
    try {
      await cam?.setFlashMode(FlashMode.off);
    } catch (_) {}
    await cam?.dispose();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _busy = false;
      _flashOn = false;
      _recordedPath = null;
      _initializing = false;
      _error = null;
      _dropping = false;
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _currentZoom = 1.0;
      _zoomUiVisible = false;
    });
  }

  void _handleExit() {
    widget.onExit?.call();
    if (widget.onExit == null) {
      Navigator.of(context).maybePop();
    }
  }

  void _handleDropped() {
    if (widget.onDropped != null) {
      widget.onDropped!();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.isActive || _recordedPath != null) return;
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      unawaited(() async {
        await controller.dispose();
        _camera = null;
      }());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera(_cameraIndex));
    }
  }

  Future<void> _boot() async {
    setState(() {
      _initializing = true;
      _error = null;
      _recordedPath = null;
    });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'Kamera bulunamadı.';
        });
        return;
      }
      final front = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = front >= 0 ? front : 0;
      await _initCamera(_cameraIndex);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Kamera izni veya erişim hatası.';
      });
    }
  }

  Future<void> _initCamera(int index) async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _error = null;
    });

    final previous = _camera;
    _camera = null;
    await previous?.dispose();

    final description = _cameras[index];
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}

      var minZoom = 1.0;
      var maxZoom = 1.0;
      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
        if (maxZoom < minZoom) maxZoom = minZoom;
      } catch (_) {}
      final initialZoom = 1.0.clamp(minZoom, maxZoom);
      try {
        await controller.setZoomLevel(initialZoom);
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraIndex = index;
        _flashOn = false;
        _initializing = false;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _currentZoom = initialZoom;
        _zoomUiVisible = false;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Kamera açılamadı. Ayarlardan izin ver.';
      });
    }
  }

  Future<void> _applyZoom(double zoom, {bool keepLabel = true}) async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (_maxZoom <= _minZoom) return;

    final clamped = zoom.clamp(_minZoom, _maxZoom).toDouble();
    if ((clamped - _currentZoom).abs() < 0.005) return;

    // Optimistic UI so rapid drag frames stay smooth.
    if (mounted) {
      setState(() {
        _currentZoom = clamped;
        if (keepLabel) _zoomUiVisible = true;
      });
    } else {
      _currentZoom = clamped;
    }

    try {
      await cam.setZoomLevel(clamped);
    } catch (_) {}
  }

  void _beginZoomGesture() {
    _zoomAtGestureStart = _currentZoom;
    _zoomGestureActive = true;
    _zoomLabelTimer?.cancel();
    if (mounted) setState(() => _zoomUiVisible = true);
  }

  void _endZoomGesture() {
    _zoomGestureActive = false;
    _scheduleHideZoomLabel();
  }

  void _scheduleHideZoomLabel() {
    _zoomLabelTimer?.cancel();
    _zoomLabelTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _zoomGestureActive) return;
      setState(() => _zoomUiVisible = false);
    });
  }

  /// [pixelsUp] = how far the finger moved up from the drag start (positive = zoom in).
  void _onZoomDragUpdate(double pixelsUp) {
    final range = _maxZoom - _minZoom;
    if (range <= 0) return;
    // ~220 logical px covers min→max (Instagram / Reels feel).
    final next = _zoomAtGestureStart + (pixelsUp / 220.0) * range;
    unawaited(_applyZoom(next));
  }

  void _onPinchZoom(double scaleFromStart) {
    if (scaleFromStart <= 0) return;
    unawaited(_applyZoom(_zoomAtGestureStart * scaleFromStart));
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording || _busy || _dropping) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    await _initCamera(next);
  }

  Future<void> _toggleFlash() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _isFront) {
      _toast(AppStrings.fromSettings().cameraFlashRearOnly);
      return;
    }
    final next = !_flashOn;
    try {
      await cam.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _flashOn = next);
    } catch (_) {
      _toast(AppStrings.fromSettings().cameraFlashUnsupported);
    }
  }

  Future<void> _toggleRecord() async {
    if (_busy || _dropping) return;
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isRecordingVideo) return;

    setState(() => _busy = true);
    try {
      await controller.startVideoRecording();
      _startElapsedTimer();
      setState(() {
        _recording = true;
        _busy = false;
      });
    } catch (_) {
      setState(() => _busy = false);
      _toast(AppStrings.fromSettings().cameraRecordFailed);
    }
  }

  Future<void> _stopRecording() async {
    final controller = _camera;
    if (controller == null || !controller.value.isRecordingVideo) {
      _stopElapsedTimer();
      setState(() => _recording = false);
      return;
    }

    setState(() => _busy = true);
    try {
      _stopElapsedTimer();
      final file = await controller.stopVideoRecording();
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      // Kayıt bitince kamerayı kapat — bellek / donanım serbest.
      _camera = null;
      await controller.dispose();

      await _openPlayback(file.path);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _busy = false;
        _flashOn = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _busy = false;
      });
      _toast(AppStrings.fromSettings().cameraStopFailed);
    }
  }

  Future<void> _openPlayback(String path) async {
    await _playback?.dispose();
    final player = VideoPlayerController.file(File(path));
    await player.initialize();
    await player.setLooping(true);
    await player.setVolume(1);
    await player.play();
    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _recordedPath = path;
      _playback = player;
    });
  }

  Future<void> _retake() async {
    await _playback?.dispose();
    _playback = null;
    _stopElapsedTimer();
    _elapsedSeconds = 0;
    _captionController.clear();
    setState(() {
      _recordedPath = null;
      _dropToCampus = false;
    });
    await _boot();
  }

  Future<void> _ensureCampusAudience() async {
    if (_hasCampusAccess) return;
    final s = AppStrings.fromSettings();
    if (!AuthService().isSignedIn) {
      _toast(s.campusEmailSignInRequired);
      return;
    }
    final profile = await showClaimStudentEmailSheet(context);
    if (!mounted) return;
    if (profile != null && profile.hasCampusAccess) {
      setState(() {
        _hasCampusAccess = true;
        _campusDomain = profile.campusDomain;
        _dropToCampus = true;
      });
      _toast(s.campusEmailLinkedToast);
    }
  }

  Future<void> _dropIt() async {
    final path = _recordedPath;
    if (path == null || _dropping) return;

    if (!SupabaseService.instance.isReady) {
      _toast(AppStrings.fromSettings().supabaseNotConfigured);
      return;
    }

    final s = AppStrings.fromSettings();
    final caption = _captionController.text.trim();
    if (caption.isEmpty) {
      _toast(_isGroupDrop ? s.captionRequiredGroup : s.captionRequired);
      return;
    }

    if (!_isGroupDrop && _dropToCampus && !_hasCampusAccess) {
      await _ensureCampusAudience();
      if (!_hasCampusAccess) {
        _toast(s.campusDropNeedsEmail);
        return;
      }
    }

    setState(() => _dropping = true);
    try {
      await _playback?.pause();

      if (_isGroupDrop) {
        await SquadGroupService().dropVideoToGroup(
          groupId: widget.groupId!,
          videoFile: File(path),
          caption: caption,
        );
        if (!mounted) return;
        _toast(s.dropToGroupToast(_groupLabel));
        _handleDropped();
        return;
      }

      final position = await LocationService.getCurrentPosition();
      final onboard = await OnboardingService.ensureOnboarded();
      // Gerçek profil adı — onboarding @anon_* yerine.
      String username = onboard.username;
      try {
        final profile = await ProfileService().fetchMyProfile();
        final fromProfile = profile?.username.trim();
        if (fromProfile != null && fromProfile.isNotEmpty) {
          username =
              fromProfile.startsWith('@') ? fromProfile : '@$fromProfile';
        } else {
          final authName = AuthService().displayName?.trim();
          if (authName != null && authName.isNotEmpty) {
            username = authName.startsWith('@') ? authName : '@$authName';
          }
        }
      } catch (_) {}

      final visibility = _dropToCampus ? 'campus' : 'public';
      await SupabaseService.instance.uploadVideo(
        file: File(path),
        latitude: position.latitude,
        longitude: position.longitude,
        username: username,
        deviceId: onboard.deviceId,
        caption: caption,
        subtitle: _dropToCampus
            ? (_campusDomain != null
                ? 'Campus · $_campusDomain'
                : 'Campus drop')
            : 'Near You drop',
        trackLabel: 'original audio',
        visibility: visibility,
      );

      if (!mounted) return;
      _toast(
        _dropToCampus
            ? s.campusDropDone(_campusDomain ?? 'kampüs')
            : s.dropDone,
      );
      _handleDropped();
    } catch (e) {
      if (!mounted) return;
      _toast(userFacingError(e, context.s));
    } finally {
      if (mounted) setState(() => _dropping = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NoolColors.acid,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: GoogleFonts.syne(
            color: NoolColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Use viewPadding so keyboard never collapses safe insets (status bar / home).
    final safeTop = mq.viewPadding.top;
    final safeBottom = mq.viewPadding.bottom;
    final keyboard = mq.viewInsets.bottom;
    // Floating nav: safeBottom + 12 + ~72px. Match layout CTA clearance.
    // When keyboard is open, sit above it instead of the floating nav.
    final aboveChrome = keyboard > 0
        ? keyboard + 12
        : (widget.onExit != null ? safeBottom + 100 : safeBottom + 20);

    return Scaffold(
      backgroundColor: NoolColors.night,
      // Don't resize the whole camera shell — pad the drop panel locally.
      // (resizeToAvoidBottomInset + viewInsets double-count crushed top chrome.)
      resizeToAvoidBottomInset: false,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_recordedPath != null && _playback != null)
              _PlaybackLayer(controller: _playback!)
            else
              _CameraLayer(
                controller: _camera,
                initializing: _initializing,
                error: _error,
                onRetry: _boot,
                onPinchZoomStart: _beginZoomGesture,
                onPinchZoom: _onPinchZoom,
                onPinchZoomEnd: _endZoomGesture,
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.only(top: safeTop),
                child: Column(
                  children: [
                    if (_recording)
                      const LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        color: NoolColors.acid,
                      )
                    else
                      const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        children: [
                          _CircleIconButton(
                            icon: NoolIconData.close,
                            onTap: _dropping ? () {} : _handleExit,
                          ),
                          const Spacer(),
                          if (_recordedPath == null)
                            Text(
                              _recording
                                  ? (_isGroupDrop
                                      ? '${_elapsedSeconds}s / ${_groupMaxSeconds}s'
                                      : '${_elapsedSeconds}s')
                                  : (_isGroupDrop ? 'KADRO' : 'REC'),
                              style: GoogleFonts.syne(
                                color: NoolColors.acid,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          const Spacer(),
                          if (_recordedPath == null) ...[
                            _CircleIconButton(
                              icon: _flashOn
                                  ? NoolIconData.flash
                                  : NoolIconData.flashOff,
                              active: _flashOn,
                              onTap: _toggleFlash,
                            ),
                            const SizedBox(width: 8),
                            _CircleIconButton(
                              icon: NoolIconData.flipCamera,
                              onTap: _flipCamera,
                            ),
                          ] else
                            const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_recordedPath == null && _zoomUiVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: aboveChrome + 108,
                child: Center(
                  child: _ZoomBadge(zoom: _currentZoom),
                ),
              ),
            if (_recordedPath == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: aboveChrome,
                child: _CaptureControls(
                  recording: _recording,
                  busy: _busy,
                  canZoom: _maxZoom > _minZoom + 0.01,
                  onRecord: _toggleRecord,
                  onZoomDragStart: _beginZoomGesture,
                  onZoomDrag: _onZoomDragUpdate,
                  onZoomDragEnd: _endZoomGesture,
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: aboveChrome,
                child: _DropPanel(
                  captionController: _captionController,
                  onRetake: _dropping ? null : _retake,
                  onDrop: _dropIt,
                  isGroupDrop: _isGroupDrop,
                  groupName: _groupLabel,
                  dropToCampus: _dropToCampus,
                  hasCampusAccess: _hasCampusAccess,
                  campusDomain: _campusDomain,
                  onAudienceChanged: (campus) async {
                    if (campus && !_hasCampusAccess) {
                      await _ensureCampusAudience();
                      return;
                    }
                    setState(() => _dropToCampus = campus);
                  },
                ),
              ),
            if (_dropping)
              _UploadingOverlay(
                isGroupDrop: _isGroupDrop,
                groupName: _groupLabel,
                dropToCampus: _dropToCampus,
                campusDomain: _campusDomain,
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadingOverlay extends StatelessWidget {
  const _UploadingOverlay({
    required this.isGroupDrop,
    required this.groupName,
    this.dropToCampus = false,
    this.campusDomain,
  });

  final bool isGroupDrop;
  final String groupName;
  final bool dropToCampus;
  final String? campusDomain;

  @override
  Widget build(BuildContext context) {
    final label = isGroupDrop
        ? 'Sadece $groupName kadrosuna bırakılıyor…'
        : dropToCampus
            ? 'Campus’e bırakılıyor${campusDomain != null ? ' · @$campusDomain' : ''}…'
            : 'Yakına bırakılıyor...';
    return ColoredBox(
      color: NoolColors.night.withValues(alpha: 0.82),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NoolLottieView.loading(width: 72, height: 72),
            const SizedBox(height: 20),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                color: NoolColors.acid,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraLayer extends StatelessWidget {
  const _CameraLayer({
    required this.controller,
    required this.initializing,
    required this.error,
    required this.onRetry,
    this.onPinchZoomStart,
    this.onPinchZoom,
    this.onPinchZoomEnd,
  });

  final CameraController? controller;
  final bool initializing;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback? onPinchZoomStart;
  final ValueChanged<double>? onPinchZoom;
  final VoidCallback? onPinchZoomEnd;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(color: NoolColors.lavender),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(context.s.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (initializing ||
        controller == null ||
        !controller!.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NoolLottieView.loading(width: 64, height: 64),
            const SizedBox(height: 14),
            Text(
              'Kamera ısınıyor…',
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) => onPinchZoomStart?.call(),
      onScaleUpdate: (details) {
        // Ignore single-finger pans on the preview — shutter owns drag-zoom.
        if (details.pointerCount < 2) return;
        onPinchZoom?.call(details.scale);
      },
      onScaleEnd: (_) => onPinchZoomEnd?.call(),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller!.value.previewSize?.height ?? 720,
            height: controller!.value.previewSize?.width ?? 1280,
            child: CameraPreview(controller!),
          ),
        ),
      ),
    );
  }
}

class _PlaybackLayer extends StatelessWidget {
  const _PlaybackLayer({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.zoom});

  final double zoom;

  @override
  Widget build(BuildContext context) {
    final label = zoom >= 10
        ? '${zoom.toStringAsFixed(0)}x'
        : '${zoom.toStringAsFixed(1)}x';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      child: Text(
        label,
        style: GoogleFonts.syne(
          color: NoolColors.acid,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }
}

/// Shutter: tap toggles record; press-hold + drag up/down zooms (IG / Snap).
class _CaptureControls extends StatefulWidget {
  const _CaptureControls({
    required this.recording,
    required this.busy,
    required this.canZoom,
    required this.onRecord,
    required this.onZoomDragStart,
    required this.onZoomDrag,
    required this.onZoomDragEnd,
  });

  final bool recording;
  final bool busy;
  final bool canZoom;
  final VoidCallback onRecord;
  final VoidCallback onZoomDragStart;
  final ValueChanged<double> onZoomDrag;
  final VoidCallback onZoomDragEnd;

  @override
  State<_CaptureControls> createState() => _CaptureControlsState();
}

class _CaptureControlsState extends State<_CaptureControls> {
  double _startY = 0;
  bool _zooming = false;

  void _finishZoomIfNeeded() {
    if (!_zooming) return;
    _zooming = false;
    widget.onZoomDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    // Tall hit area: drag continues via GestureDetector even above the button.
    return SizedBox(
      height: 220,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.busy ? null : widget.onRecord,
          onVerticalDragStart: !widget.canZoom || widget.busy
              ? null
              : (details) {
                  _startY = details.globalPosition.dy;
                  _zooming = false;
                },
          onVerticalDragUpdate: !widget.canZoom || widget.busy
              ? null
              : (details) {
                  final pixelsUp = _startY - details.globalPosition.dy;
                  if (!_zooming) {
                    _zooming = true;
                    widget.onZoomDragStart();
                  }
                  widget.onZoomDrag(pixelsUp);
                },
          onVerticalDragEnd:
              !widget.canZoom ? null : (_) => _finishZoomIfNeeded(),
          onVerticalDragCancel: !widget.canZoom ? null : _finishZoomIfNeeded,
          child: Padding(
            padding: const EdgeInsets.only(top: 120),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: widget.recording ? 72 : 84,
              height: widget.recording ? 72 : 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    widget.recording ? NoolColors.tangerine : NoolColors.night,
                border: Border.all(
                  color:
                      widget.recording ? NoolColors.tangerine : NoolColors.acid,
                  width: 5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Center(
                child: widget.recording
                    ? Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: NoolColors.ink,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: NoolColors.ink, width: 2),
                        ),
                      )
                    : Container(
                        width: 62,
                        height: 62,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: NoolColors.acid,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropPanel extends StatelessWidget {
  const _DropPanel({
    required this.captionController,
    required this.onRetake,
    required this.onDrop,
    required this.isGroupDrop,
    required this.groupName,
    this.dropToCampus = false,
    this.hasCampusAccess = false,
    this.campusDomain,
    this.onAudienceChanged,
  });

  final TextEditingController captionController;
  final VoidCallback? onRetake;
  final VoidCallback onDrop;
  final bool isGroupDrop;
  final String groupName;
  final bool dropToCampus;
  final bool hasCampusAccess;
  final String? campusDomain;
  final ValueChanged<bool>? onAudienceChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final dropLabel = isGroupDrop
        ? s.dropToGroupOnly(groupName)
        : dropToCampus
            ? s.campusDropLabel
            : s.nearDropLabel;

    // Safe area / nav clearance handled by parent Positioned.bottom.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: NoolColors.night.withValues(alpha: 0.92),
          border: Border.all(color: NoolColors.ink, width: 3.5),
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
              s.cameraPreview,
              style: GoogleFonts.syne(
                color: NoolColors.acid,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            if (isGroupDrop) ...[
              const SizedBox(height: 10),
              Container(
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
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: NoolColors.ink,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.dropToGroupOnly(groupName),
                        style: GoogleFonts.syne(
                          color: NoolColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _AudienceChip(
                      label: s.campusAudienceNear,
                      selected: !dropToCampus,
                      onTap: () => onAudienceChanged?.call(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AudienceChip(
                      label: hasCampusAccess && campusDomain != null
                          ? '${s.campusAudienceCampus}\n@$campusDomain'
                          : s.campusAudienceCampus,
                      selected: dropToCampus,
                      onTap: () => onAudienceChanged?.call(true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s.campusAudienceHint,
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            Container(
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
                controller: captionController,
                maxLines: 2,
                maxLength: 140,
                style: GoogleFonts.syne(
                  color: NoolColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                cursorColor: NoolColors.acid,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: isGroupDrop
                      ? 'Kadronun bilmesi gereken…'
                      : 'Müzik kulübünde şok kavga!',
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRetake,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NoolColors.white,
                      side: const BorderSide(
                        color: NoolColors.ink,
                        width: 3,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Yeniden',
                      style: GoogleFonts.syne(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: NoolColors.ink,
                          offset: Offset(4, 4),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Material(
                      color: isGroupDrop || dropToCampus
                          ? NoolColors.acid
                          : NoolColors.tangerine,
                      child: InkWell(
                        onTap: onDrop,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: NoolColors.ink,
                              width: 3.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            dropLabel,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.syne(
                              color: NoolColors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: isGroupDrop ? 12 : 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? NoolColors.acid : NoolColors.night,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: NoolColors.ink, width: 3),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: NoolColors.ink,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.syne(
              color: selected ? NoolColors.ink : NoolColors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final NoolIconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              active ? NoolColors.acid : Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: NoolColors.ink, width: 3),
          boxShadow: const [
            BoxShadow(
              color: NoolColors.ink,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: NoolIcon(
          icon,
          color: active ? NoolColors.ink : NoolColors.white,
          size: 22,
        ),
      ),
    );
  }
}
