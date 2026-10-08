import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../models/campus_hotspot.dart';
import '../theme/colors.dart';

/// Hotspot yoğunluğuna göre lavender → acid → tangerine ısı daireleri + pinler.
class NoolHeatMapLayers extends StatelessWidget {
  const NoolHeatMapLayers({
    super.key,
    required this.hotspots,
    required this.selectedId,
    required this.onSelect,
    this.pulse = 1,
  });

  final List<CampusHotspot> hotspots;
  final String? selectedId;
  final ValueChanged<CampusHotspot> onSelect;

  /// 0.9–1.1 arası pulse faktörü (en sıcak noktalar için).
  final double pulse;

  /// Yakın pinler için etiket çakışma eşiği (metre) — crush’ı azalt.
  static const double _labelProximityMeters = 130;

  static const _distance = Distance();

  /// Neo-brutal stagger slot’ları — daha açık offset, okunabilir kalsın.
  static const List<Offset> _staggerSlots = [
    Offset(0, 0),
    Offset(24, -18),
    Offset(-24, -18),
    Offset(28, 16),
    Offset(-28, 16),
    Offset(0, -28),
    Offset(18, 26),
    Offset(-18, 26),
  ];

  static int _maxDrops(List<CampusHotspot> spots) {
    if (spots.isEmpty) return 1;
    return spots.map((s) => s.dropCount).fold<int>(1, math.max);
  }

  /// 0..1 yoğunluk.
  static double intensity(CampusHotspot spot, int maxDrops) {
    return (spot.dropCount / maxDrops).clamp(0.15, 1.0);
  }

  static Color heatColor(double t) {
    if (t < 0.45) {
      return Color.lerp(NoolColors.lavender, NoolColors.acid, t / 0.45)!;
    }
    return Color.lerp(
        NoolColors.acid, NoolColors.tangerine, (t - 0.45) / 0.55)!;
  }

  /// Seçili / sıcak öncelikli; yakınlarda yalnızca bir sayaç etiketi, diğerleri nokta.
  List<_PinPlacement> _placements() {
    final ordered = [...hotspots]..sort((a, b) {
        if (a.id == selectedId) return -1;
        if (b.id == selectedId) return 1;
        return b.dropCount.compareTo(a.dropCount);
      });

    final labeled = <CampusHotspot>[];
    final out = <_PinPlacement>[];

    for (final spot in ordered) {
      final nearbyLabeled = <CampusHotspot>[];
      for (final other in labeled) {
        final meters = _distance(
          LatLng(spot.latitude, spot.longitude),
          LatLng(other.latitude, other.longitude),
        );
        if (meters < _labelProximityMeters) {
          nearbyLabeled.add(other);
        }
      }

      final isSelected = spot.id == selectedId;
      // Seçili her zaman etiket; aksi halde yakınında etiketli pin yoksa göster.
      final showCount = isSelected || nearbyLabeled.isEmpty;
      final conflictIndex = nearbyLabeled.length;
      final slot = _staggerSlots[conflictIndex % _staggerSlots.length];
      // Seçili + çakışma: stagger’ı biraz büyüt ki seçim baskın kalsın.
      final scale = isSelected && conflictIndex > 0 ? 1.25 : 1.0;
      final offset = Offset(slot.dx * scale, slot.dy * scale);

      if (showCount) labeled.add(spot);

      out.add(
        _PinPlacement(
          spot: spot,
          showCount: showCount,
          offset: offset,
        ),
      );
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final maxDrops = _maxDrops(hotspots);
    final placements = _placements();

    return Stack(
      children: [
        MarkerLayer(
          markers: [
            for (final spot in hotspots)
              Marker(
                point: LatLng(spot.latitude, spot.longitude),
                width: _blobSize(spot, maxDrops) * pulse,
                height: _blobSize(spot, maxDrops) * pulse,
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: _HeatBlob(
                    color: heatColor(intensity(spot, maxDrops)),
                    intensity: intensity(spot, maxDrops),
                  ),
                ),
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final p in placements)
              Marker(
                point: LatLng(p.spot.latitude, p.spot.longitude),
                // Offset’li etiketler kesilmesin diye geniş hit/layout kutusu.
                width: p.showCount ? 112 : 28,
                height: p.showCount ? 80 : 28,
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: p.offset,
                  child: Align(
                    alignment: Alignment.center,
                    child: _HeatPin(
                      spot: p.spot,
                      selected: p.spot.id == selectedId,
                      showCount: p.showCount,
                      color: heatColor(intensity(p.spot, maxDrops)),
                      onTap: () => onSelect(p.spot),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  double _blobSize(CampusHotspot spot, int maxDrops) {
    final t = intensity(spot, maxDrops);
    return 70 + t * 110;
  }
}

class _PinPlacement {
  const _PinPlacement({
    required this.spot,
    required this.showCount,
    required this.offset,
  });

  final CampusHotspot spot;
  final bool showCount;
  final Offset offset;
}

class _HeatBlob extends StatelessWidget {
  const _HeatBlob({required this.color, required this.intensity});

  final Color color;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.55 * intensity + 0.15),
            color.withValues(alpha: 0.28 * intensity),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

class _HeatPin extends StatelessWidget {
  const _HeatPin({
    required this.spot,
    required this.selected,
    required this.showCount,
    required this.color,
    required this.onTap,
  });

  final CampusHotspot spot;
  final bool selected;
  final bool showCount;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!showCount) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: selected ? color : NoolColors.night,
            border: Border.all(color: NoolColors.ink, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
        ),
      );
    }

    final bg = selected ? color : NoolColors.night;
    final fg = selected ? NoolColors.ink : NoolColors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: NoolColors.ink, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: NoolColors.ink,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          '${spot.dropCount}',
          textAlign: TextAlign.center,
          style: GoogleFonts.syne(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            height: 1,
          ),
        ),
      ),
    );
  }
}
