import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Nool Lottie asset yolları
/// ([LottieFiles](https://lottiefiles.com) ücretsiz + marka renkleri).
abstract final class NoolLottie {
  static const radar = 'assets/lottie/radar_scan.json';
  static const neonLoading = 'assets/lottie/neon_loading.json';
  static const acidLoader = 'assets/lottie/acid_loader.json';
  static const successCheck = 'assets/lottie/success_check.json';
  static const firePulse = 'assets/lottie/fire_pulse.json';
  static const fireEnergy = 'assets/lottie/fire_energy.json';
}

/// Asit / tangerine Lottie sarmalayıcı — loop veya one-shot.
class NoolLottieView extends StatelessWidget {
  const NoolLottieView({
    super.key,
    required this.asset,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.animate = true,
  });

  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final bool animate;

  /// Radar tarama (feed).
  const NoolLottieView.radar({
    super.key,
    this.width = 220,
    this.height = 220,
    this.fit = BoxFit.contain,
  })  : asset = NoolLottie.radar,
        repeat = true,
        animate = true;

  /// Neon / asit loading.
  const NoolLottieView.loading({
    super.key,
    this.width = 96,
    this.height = 96,
    this.fit = BoxFit.contain,
    bool compact = false,
  })  : asset = compact ? NoolLottie.acidLoader : NoolLottie.neonLoading,
        repeat = true,
        animate = true;

  /// Başarı check (one-shot loop kapalı).
  const NoolLottieView.success({
    super.key,
    this.width = 120,
    this.height = 120,
    this.fit = BoxFit.contain,
  })  : asset = NoolLottie.successCheck,
        repeat = false,
        animate = true;

  /// Trend / vibe ateş.
  const NoolLottieView.fire({
    super.key,
    this.width = 72,
    this.height = 72,
    this.fit = BoxFit.contain,
    bool energy = false,
  })  : asset = energy ? NoolLottie.fireEnergy : NoolLottie.firePulse,
        repeat = true,
        animate = true;

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      repeat: repeat,
      animate: animate,
      frameRate: FrameRate.max,
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFADFF2F),
              strokeWidth: 2.5,
            ),
          ),
        );
      },
    );
  }
}
