import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';

/// Kozmik night atmosfer — hafif gradient + soft glow blob’lar.
class NoolAtmosphere extends StatelessWidget {
  const NoolAtmosphere({
    super.key,
    this.child,
    this.intensity = 1,
    this.accent = AtmosphereAccent.acid,
  });

  final Widget? child;
  final double intensity;
  final AtmosphereAccent accent;

  @override
  Widget build(BuildContext context) {
    final glow = switch (accent) {
      AtmosphereAccent.acid => NoolColors.acid,
      AtmosphereAccent.tangerine => NoolColors.tangerine,
      AtmosphereAccent.lavender => NoolColors.lavender,
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                NoolColors.night,
                Color.lerp(NoolColors.night, glow, 0.10 * intensity)!,
                Color.lerp(NoolColors.night, NoolColors.lavender, 0.12 * intensity)!,
                NoolColors.night,
              ],
              stops: const [0.0, 0.35, 0.7, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: _GlowBlob(
            size: 220,
            color: glow.withOpacity(0.14 * intensity),
          ),
        ),
        Positioned(
          bottom: 40,
          left: -70,
          child: _GlowBlob(
            size: 180,
            color: NoolColors.tangerine.withOpacity(0.10 * intensity),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

enum AtmosphereAccent { acid, tangerine, lavender }

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

/// Basınca hafif çöken brutal buton hissi.
class BrutalPressable extends StatefulWidget {
  const BrutalPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.offset = const Offset(4, 4),
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Offset offset;
  final bool enabled;

  @override
  State<BrutalPressable> createState() => _BrutalPressableState();
}

class _BrutalPressableState extends State<BrutalPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _down && widget.enabled;
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap?.call();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          pressed ? widget.offset.dx : 0,
          pressed ? widget.offset.dy : 0,
          0,
        ),
        decoration: BoxDecoration(
          boxShadow: pressed
              ? null
              : [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: widget.offset,
                    blurRadius: 0,
                  ),
                ],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Glass + ink border panel — neo-brutal frost.
class NoolGlassPanel extends StatelessWidget {
  const NoolGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderWidth = 3,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderWidth;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (tint ?? NoolColors.lavender).withOpacity(0.12),
            border: Border.all(color: NoolColors.ink, width: borderWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Sekme / sayfa geçişi — fade + hafif slide.
Route<T> noolRoute<T>({
  required Widget page,
  Duration duration = const Duration(milliseconds: 380),
  Offset begin = const Offset(0, 0.05),
}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Hafif noise-like diagonal scan çizgisi (dekoratif).
class NoolScanLines extends StatelessWidget {
  const NoolScanLines({super.key, this.opacity = 0.04});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanPainter(opacity: opacity),
        size: Size.infinite,
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NoolColors.white.withOpacity(opacity)
      ..strokeWidth = 1;
    const gap = 6.0;
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

/// Acid shimmer text pulse (marka vurgusu).
class NoolPulse extends StatefulWidget {
  const NoolPulse({super.key, required this.child, this.min = 0.96, this.max = 1.04});

  final Widget child;
  final double min;
  final double max;

  @override
  State<NoolPulse> createState() => _NoolPulseState();
}

class _NoolPulseState extends State<NoolPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: widget.min, end: widget.max).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Rastgele hafif parallax drift (arka plan blob).
class NoolDrift extends StatefulWidget {
  const NoolDrift({super.key, required this.child});

  final Widget child;

  @override
  State<NoolDrift> createState() => _NoolDriftState();
}

class _NoolDriftState extends State<NoolDrift>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final double _dx;
  late final double _dy;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _dx = 8 + rng.nextDouble() * 10;
    _dy = 6 + rng.nextDouble() * 8;
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
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
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(_dx * (t - 0.5), _dy * (t - 0.5)),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
