import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../icons/nool_icons.dart';
import '../services/location_service.dart';
import '../services/onboarding_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_lottie.dart';

const _maxRecordSeconds = 15;

/// Mystery Camera — 15sn kayıt, gerçek zamanlı piksel filtresi, Supabase drop.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.isActive = true,
    this.onExit,
    this.onDropped,
  });

  final bool isActive;
  final VoidCallback? onExit;
  final VoidCallback? onDropped;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  bool _initializing = true;
  String? _error;
  bool _mysteryMode = true;
  bool _flashOn = false;
  bool _recording = false;
  bool _busy = false;

  String? _recordedPath;
  VideoPlayerController? _playback;

  bool _robotizeVoice = false;
  bool _dropping = false;
  final _captionController = TextEditingController();

  late final AnimationController _progressController;

  bool get _isFront {
    if (_cameras.isEmpty || _cameraIndex >= _cameras.length) return true;
    return _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _maxRecordSeconds),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _recording) {
          unawaited(_stopRecording());
        }
      });
    if (widget.isActive) {
      unawaited(_boot());
    } else {
      _initializing = false;
    }
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
    _progressController.dispose();
    _captionController.dispose();
    _playback?.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _tearDownCamera() async {
    if (_recording) {
      try {
        await _camera?.stopVideoRecording();
      } catch (_) {}
    }
    _progressController.stop();
    _progressController.reset();
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
      unawaited(controller.dispose());
      _camera = null;
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
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraIndex = index;
        _flashOn = false;
        _initializing = false;
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

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording || _busy || _dropping) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    await _initCamera(next);
  }

  Future<void> _toggleFlash() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _isFront) {
      _toast('Flaş yalnızca arka kamerada.');
      return;
    }
    final next = !_flashOn;
    try {
      await cam.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _flashOn = next);
    } catch (_) {
      _toast('Flaş bu cihazda desteklenmiyor.');
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
      _progressController
        ..reset()
        ..forward();
      setState(() {
        _recording = true;
        _busy = false;
      });
    } catch (_) {
      setState(() => _busy = false);
      _toast('Kayıt başlatılamadı');
    }
  }

  Future<void> _stopRecording() async {
    final controller = _camera;
    if (controller == null || !controller.value.isRecordingVideo) {
      setState(() => _recording = false);
      return;
    }

    setState(() => _busy = true);
    try {
      _progressController.stop();
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
      _toast('Kayıt durdurulamadı');
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
      if (_captionController.text.trim().isEmpty) {
        _captionController.text = _mysteryMode
            ? 'gizem drop — yüz yok, kaos var'
            : '';
      }
    });
  }

  Future<void> _retake() async {
    await _playback?.dispose();
    _playback = null;
    _progressController.reset();
    _captionController.clear();
    setState(() {
      _recordedPath = null;
      _robotizeVoice = false;
    });
    await _boot();
  }

  Future<void> _dropIt() async {
    final path = _recordedPath;
    if (path == null || _dropping) return;

    if (!SupabaseService.instance.isReady) {
      _toast('Supabase bağlı değil — dart-define anahtarlarını kontrol et.');
      return;
    }

    final caption = _captionController.text.trim();
    if (caption.isEmpty) {
      _toast('Bir açıklama yaz — kampüs ne olduğunu bilsin.');
      return;
    }

    setState(() => _dropping = true);
    try {
      final position = await LocationService.getCurrentPosition();
      final onboard = await OnboardingService.ensureOnboarded();

      // Kamera zaten kapalı; playback’i de durdur.
      await _playback?.pause();

      await SupabaseService.instance.uploadVideo(
        file: File(path),
        latitude: position.latitude,
        longitude: position.longitude,
        username: onboard.username,
        deviceId: onboard.deviceId,
        caption: caption,
        subtitle: _mysteryMode ? 'Mystery Mode' : 'Campus drop',
        trackLabel:
            _robotizeVoice ? 'anon voice (robot) — soon' : 'original audio',
      );

      if (!mounted) return;
      _toast('Drop edildi. Kaos yolda.');
      _handleDropped();
    } catch (e) {
      _toast('Yükleme başarısız: $e');
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
    final shellPad = widget.onExit != null ? 72.0 : 0.0;

    return Scaffold(
      backgroundColor: NoolColors.night,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_recordedPath != null && _playback != null)
              _PlaybackLayer(
                controller: _playback!,
                mysteryMode: _mysteryMode,
              )
            else
              _CameraLayer(
                controller: _camera,
                initializing: _initializing,
                error: _error,
                mysteryMode: _mysteryMode,
                onRetry: _boot,
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (_, __) {
                        final show = _recording ||
                            (_progressController.value > 0 &&
                                _recordedPath == null);
                        return Opacity(
                          opacity: show ? 1 : 0,
                          child: LinearProgressIndicator(
                            value: _progressController.value.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Colors.white12,
                            color: NoolColors.acid,
                          ),
                        );
                      },
                    ),
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
                                  ? '${(_progressController.value * _maxRecordSeconds).ceil().clamp(0, _maxRecordSeconds)}s'
                                  : 'MAX ${_maxRecordSeconds}s',
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
                            const SizedBox(width: 96),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_recordedPath == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: EdgeInsets.only(bottom: shellPad),
                  child: _CaptureControls(
                    mysteryMode: _mysteryMode,
                    recording: _recording,
                    busy: _busy,
                    onMysteryChanged: (v) => setState(() => _mysteryMode = v),
                    onRecord: _toggleRecord,
                  ),
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: shellPad + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: _DropPanel(
                    captionController: _captionController,
                    robotizeVoice: _robotizeVoice,
                    onRobotizeChanged: (v) =>
                        setState(() => _robotizeVoice = v),
                    onRetake: _dropping ? null : _retake,
                    onDrop: _dropIt,
                  ),
                ),
              ),
            if (_dropping) const _UploadingOverlay(),
          ],
        ),
      ),
    );
  }
}

class _UploadingOverlay extends StatelessWidget {
  const _UploadingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NoolColors.night.withOpacity(0.82),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NoolLottieView.loading(width: 72, height: 72),
            const SizedBox(height: 20),
            Text(
              'Kaos kampüse bırakılıyor...',
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
    required this.mysteryMode,
    required this.onRetry,
  });

  final CameraController? controller;
  final bool initializing;
  final String? error;
  final bool mysteryMode;
  final VoidCallback onRetry;

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
                child: const Text('Yeniden dene'),
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

    return _MysteryPreview(
      mysteryMode: mysteryMode,
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
  const _PlaybackLayer({
    required this.controller,
    required this.mysteryMode,
  });

  final VideoPlayerController controller;
  final bool mysteryMode;

  @override
  Widget build(BuildContext context) {
    return _MysteryPreview(
      mysteryMode: mysteryMode,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

/// Gizem Modu: ColorFiltered + BackdropFilter + mozaik painter.
class _MysteryPreview extends StatelessWidget {
  const _MysteryPreview({
    required this.mysteryMode,
    required this.child,
  });

  final bool mysteryMode;
  final Widget child;

  static const _glitchFilter = ColorFilter.matrix(<double>[
    0.7, 0.15, 0.15, 0, 12,
    0.1, 0.85, 0.05, 0, 0,
    0.2, 0.1, 0.9, 0, 18,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (!mysteryMode) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: _glitchFilter,
          child: child,
        ),
        // Hafif buz + mozaik — yüz gizleme hissi
        IgnorePointer(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xCCFFFFFF),
                    Color(0x66FFFFFF),
                    Color(0xEEFFFFFF),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ).createShader(bounds);
              },
              child: const CustomPaint(
                painter: _MysteryMosaicPainter(),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
        const IgnorePointer(
          child: CustomPaint(
            painter: _MysteryMosaicPainter(),
            child: SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _MysteryMosaicPainter extends CustomPainter {
  const _MysteryMosaicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 16.0;
    final cols = (size.width / tile).ceil();
    final rows = (size.height / tile).ceil();
    final rng = math.Random(42);

    final faceCenter = Offset(size.width * 0.5, size.height * 0.36);
    final faceRx = size.width * 0.24;
    final faceRy = size.height * 0.17;

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final rect = Rect.fromLTWH(x * tile, y * tile, tile + 0.6, tile + 0.6);
        final center = rect.center;
        final nx = (center.dx - faceCenter.dx) / faceRx;
        final ny = (center.dy - faceCenter.dy) / faceRy;
        final inFace = (nx * nx + ny * ny) <= 1.2;

        if (!inFace && rng.nextDouble() > 0.07) continue;

        final shade = inFace ? 35 + rng.nextInt(170) : 18 + rng.nextInt(70);
        final alpha = inFace ? 0.58 + rng.nextDouble() * 0.35 : 0.16;
        final shift = inFace ? (rng.nextDouble() * 5 - 2.5) : 0.0;

        canvas.drawRect(
          rect.translate(shift, 0),
          Paint()
            ..color = Color.fromRGBO(
              shade,
              (shade * 0.85).round().clamp(0, 255),
              (shade * 1.12 + 18).round().clamp(0, 255),
              alpha,
            ),
        );

        if (inFace && rng.nextDouble() > 0.72) {
          canvas.drawRect(
            rect.translate(-shift * 1.5, 1),
            Paint()
              ..color = NoolColors.acid.withOpacity(0.14)
              ..blendMode = BlendMode.plus,
          );
        }
      }
    }

    final linePaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.mysteryMode,
    required this.recording,
    required this.busy,
    required this.onMysteryChanged,
    required this.onRecord,
  });

  final bool mysteryMode;
  final bool recording;
  final bool busy;
  final ValueChanged<bool> onMysteryChanged;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: mysteryMode
                        ? NoolColors.acid
                        : Colors.black.withOpacity(0.45),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.blur_on_rounded,
                        size: 18,
                        color: mysteryMode ? NoolColors.ink : NoolColors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'GİZEM',
                        style: GoogleFonts.syne(
                          color:
                              mysteryMode ? NoolColors.ink : NoolColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      Transform.scale(
                        scale: 0.85,
                        child: Switch(
                          value: mysteryMode,
                          activeColor: NoolColors.ink,
                          activeTrackColor: NoolColors.acid,
                          inactiveThumbColor: NoolColors.lavender,
                          inactiveTrackColor: Colors.white24,
                          onChanged: onMysteryChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: busy ? null : onRecord,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: recording ? NoolColors.tangerine : NoolColors.acid,
                border: Border.all(color: NoolColors.ink, width: 4),
                boxShadow: const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: NoolIcon(
                recording ? NoolIconData.stop : NoolIconData.record,
                color: NoolColors.ink,
                size: recording ? 32 : 36,
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

class _DropPanel extends StatelessWidget {
  const _DropPanel({
    required this.captionController,
    required this.robotizeVoice,
    required this.onRobotizeChanged,
    required this.onRetake,
    required this.onDrop,
  });

  final TextEditingController captionController;
  final bool robotizeVoice;
  final ValueChanged<bool> onRobotizeChanged;
  final VoidCallback? onRetake;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 12 + bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.16),
                width: 1.2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Önizleme',
                  style: GoogleFonts.syne(
                    color: NoolColors.acid,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: 0.55,
                  child: IgnorePointer(
                    child: _GlassToggle(
                      label: 'Anonim Sesi Robotlaştır',
                      value: robotizeVoice,
                      onChanged: onRobotizeChanged,
                      trailing: Text(
                        'simülasyon',
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
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
                      hintText: 'Müzik kulübünde şok kavga!',
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
                          color: NoolColors.tangerine,
                          child: InkWell(
                            onTap: onDrop,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 15),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: NoolColors.ink,
                                  width: 3.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Kampüse Bırak (Drop It)',
                                style: GoogleFonts.syne(
                                  color: NoolColors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
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
        ),
      ),
    );
  }
}

class _GlassToggle extends StatelessWidget {
  const _GlassToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: NoolColors.acid,
              checkColor: NoolColors.ink,
              side: const BorderSide(color: NoolColors.lavender, width: 2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.syne(
                color: NoolColors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
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
    return Material(
      color: active
          ? NoolColors.acid.withOpacity(0.9)
          : Colors.black.withOpacity(0.4),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white24, width: 1.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: NoolIcon(
            icon,
            color: active ? NoolColors.ink : NoolColors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}
