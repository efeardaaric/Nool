import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../theme/colors.dart';

/// Trend sekmesi giriş animasyonu — asit radar sweep + brutalist TREND stamp.
/// ~1.6s, tap ile atlanabilir; [onFinished] ile haritayı açar.
class NoolTrendIntro extends StatefulWidget {
  const NoolTrendIntro({
    super.key,
    required this.onFinished,
    this.minDuration = const Duration(milliseconds: 1600),
  });

  final VoidCallback onFinished;
  final Duration minDuration;

  @override
  State<NoolTrendIntro> createState() => _NoolTrendIntroState();
}

class _NoolTrendIntroState extends State<NoolTrendIntro>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  late final AnimationController _sweep;
  late final Animation<double> _fadeIn;
  late final Animation<double> _fadeOut;
  late final Animation<double> _stampScale;
  late final Animation<double> _stampOpacity;
  late final Animation<double> _ringExpand;

  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: widget.minDuration,
    );
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _fadeIn = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.0, 0.18, curve: Curves.easeOut),
    );
    _ringExpand = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
    );
    _stampScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.55, end: 0.92)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.28, 0.55),
      ),
    );
    _stampOpacity = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.28, 0.42, curve: Curves.easeOut),
    );
    _fadeOut = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.78, 1.0, curve: Curves.easeIn),
    );

    _master.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_finishing || !mounted) return;
    _finishing = true;
    widget.onFinished();
  }

  void _skip() {
    if (_finishing) return;
    _master.animateTo(
      1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _master.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: Listenable.merge([_master, _sweep]),
        builder: (context, _) {
          final out = _fadeOut.value;
          final opacity = (_fadeIn.value * (1.0 - out)).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: ColoredBox(
              color: NoolColors.night,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Soft acid / tangerine atmosphere — not flat night.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.15),
                        radius: 1.05,
                        colors: [
                          Color(0x33ADFF2F),
                          Color(0x220D0A1C),
                          NoolColors.night,
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.scale(
                      scale: 0.72 + (_ringExpand.value * 0.28),
                      child: SizedBox(
                        width: 280,
                        height: 280,
                        child: CustomPaint(
                          painter: _TrendRadarPainter(
                            sweep: _sweep.value,
                            pulse: _master.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Opacity(
                      opacity: _stampOpacity.value.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: _stampScale.value,
                        child: Transform.rotate(
                          angle: -0.06,
                          child: const _TrendStamp(),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.paddingOf(context).bottom + 100,
                    child: Opacity(
                      opacity: (_stampOpacity.value * 0.7).clamp(0.0, 1.0),
                      child: Text(
                        AppStrings.of(context).trendIntroSkip,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrendStamp extends StatelessWidget {
  const _TrendStamp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: NoolColors.acid,
        border: Border.all(color: NoolColors.ink, width: 4),
        boxShadow: const [
          BoxShadow(
            color: NoolColors.ink,
            offset: Offset(5, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        'TREND',
        style: GoogleFonts.syne(
          color: NoolColors.ink,
          fontWeight: FontWeight.w800,
          fontSize: 36,
          letterSpacing: 2.5,
          height: 1,
        ),
      ),
    );
  }
}

class _TrendRadarPainter extends CustomPainter {
  _TrendRadarPainter({required this.sweep, required this.pulse});

  final double sweep;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.46;

    // Outer brutal square frame.
    final frame = Paint()
      ..color = NoolColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    final frameRect = Rect.fromCenter(
      center: c,
      width: maxR * 2.05,
      height: maxR * 2.05,
    );
    canvas.drawRect(frameRect, frame);
    canvas.drawRect(
      frameRect.shift(const Offset(3, 3)),
      Paint()
        ..color = NoolColors.ink.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Concentric rings.
    for (var i = 1; i <= 3; i++) {
      final r = maxR * (i / 3);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = NoolColors.acid.withValues(alpha: 0.18 + i * 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 3 ? 3.2 : 2.2,
      );
    }

    // Crosshair ticks (compass feel, neo-brutal — not a soft dial).
    final tickPaint = Paint()
      ..color = NoolColors.lavender.withValues(alpha: 0.55)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;
    for (var a = 0; a < 4; a++) {
      final ang = a * math.pi / 2;
      final inner = Offset(
        c.dx + math.cos(ang) * (maxR * 0.78),
        c.dy + math.sin(ang) * (maxR * 0.78),
      );
      final outer = Offset(
        c.dx + math.cos(ang) * maxR,
        c.dy + math.sin(ang) * maxR,
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Sweep wedge — acid arc.
    final angle = sweep * math.pi * 2 - math.pi / 2;
    const wedge = 0.85;
    final sweepPath = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(
        Rect.fromCircle(center: c, radius: maxR),
        angle - wedge,
        wedge,
        false,
      )
      ..close();
    canvas.drawPath(
      sweepPath,
      Paint()..color = NoolColors.acid.withValues(alpha: 0.22),
    );
    // Leading edge highlight.
    final tip = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(
        Rect.fromCircle(center: c, radius: maxR),
        angle - 0.18,
        0.18,
        false,
      )
      ..close();
    canvas.drawPath(
      tip,
      Paint()..color = NoolColors.acid.withValues(alpha: 0.55),
    );

    // Sweep arm — thick ink + acid.
    final armEnd = Offset(
      c.dx + math.cos(angle) * maxR,
      c.dy + math.sin(angle) * maxR,
    );
    canvas.drawLine(
      c,
      armEnd,
      Paint()
        ..color = NoolColors.ink
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.square,
    );
    canvas.drawLine(
      c,
      armEnd,
      Paint()
        ..color = NoolColors.acid
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.square,
    );

    // Heat blips — 3 intentional pulses on the ring.
    final blips = <(double, Color)>[
      (0.15, NoolColors.tangerine),
      (0.42, NoolColors.acid),
      (0.78, NoolColors.tangerine),
    ];
    for (final (t, color) in blips) {
      final ang = t * math.pi * 2 - math.pi / 2;
      final dist = maxR * (0.55 + 0.28 * ((pulse + t) % 1.0));
      final p = Offset(
        c.dx + math.cos(ang) * dist,
        c.dy + math.sin(ang) * dist,
      );
      final blink = 0.55 + 0.45 * math.sin((pulse + t) * math.pi * 2);
      canvas.drawRect(
        Rect.fromCenter(center: p, width: 9, height: 9),
        Paint()..color = color.withValues(alpha: blink.clamp(0.35, 1.0)),
      );
      canvas.drawRect(
        Rect.fromCenter(center: p, width: 9, height: 9),
        Paint()
          ..color = NoolColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Core.
    canvas.drawCircle(c, 10, Paint()..color = NoolColors.acid);
    canvas.drawCircle(
      c,
      10,
      Paint()
        ..color = NoolColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendRadarPainter oldDelegate) =>
      oldDelegate.sweep != sweep || oldDelegate.pulse != pulse;
}
