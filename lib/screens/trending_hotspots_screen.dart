import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../config/supabase_config.dart';
import '../l10n/app_strings.dart';
import '../models/campus_hotspot.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_heat_map_layer.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import '../widgets/nool_trend_intro.dart';

/// Çevre yoğunluk haritası — konum başına video sayısı + 500m…20km halkaları.
class TrendingHotspotsScreen extends StatefulWidget {
  const TrendingHotspotsScreen({
    super.key,
    this.isActive = true,
    this.onHotspotSelected,
  });

  /// Sekme görünürken yenilemek için.
  final bool isActive;

  /// Pin / kart tıklanınca feed filtresi + sekme geçişi.
  final ValueChanged<CampusHotspot>? onHotspotSelected;

  @override
  State<TrendingHotspotsScreen> createState() => _TrendingHotspotsScreenState();
}

class _TrendingHotspotsScreenState extends State<TrendingHotspotsScreen>
    with SingleTickerProviderStateMixin {
  List<CampusHotspot> _hotspots = const [];
  bool _loading = true;
  String? _error;
  CampusHotspot? _selected;
  LatLng? _center;
  double _activeRadiusMeters = SupabaseConfig.hotspotRadiusMeters;
  int _totalVideos = 0;

  /// null = yoğunluğa göre otomatik genişle; aksi halde sabit halka.
  double? _forcedRadiusMeters;

  /// İlk Trend girişi — asit radar + TREND stamp (oturumda bir kez).
  bool _showIntro = false;
  bool _introDone = true;
  bool _playedIntroOnce = false;

  final _mapController = MapController();
  late final AnimationController _pulse;
  int _loadGeneration = 0;
  int _introKey = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    if (widget.isActive) {
      _armIntro();
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant TrendingHotspotsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      setState(() => _armIntro());
      _load(soft: _center != null);
    }
  }

  void _armIntro() {
    if (_playedIntroOnce) return;
    _playedIntroOnce = true;
    _showIntro = true;
    _introDone = false;
    _introKey++;
  }

  void _onIntroFinished() {
    if (!mounted || _introDone) return;
    setState(() {
      _introDone = true;
      _showIntro = false;
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load({bool soft = false}) async {
    final generation = ++_loadGeneration;
    final s = AppStrings.of(context);

    setState(() {
      if (!soft) _loading = true;
      _error = null;
    });

    try {
      final supabase = SupabaseService.instance;
      late final double lat;
      late final double lng;

      try {
        if (supabase.hasSessionLocation) {
          lat = supabase.sessionLatitude!;
          lng = supabase.sessionLongitude!;
        } else {
          final pos = await LocationService.getCurrentPosition();
          lat = pos.latitude;
          lng = pos.longitude;
          supabase.setSessionLocation(latitude: lat, longitude: lng);
        }
      } catch (_) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _loading = false;
          _error = s.trendGpsError;
          _hotspots = const [];
          _center = null;
          _totalVideos = 0;
        });
        return;
      }

      final center = LatLng(lat, lng);

      if (!supabase.isReady) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _loading = false;
          _hotspots = const [];
          _center = center;
          _selected = null;
          _totalVideos = 0;
          _error = null;
        });
        _moveTo(center, _activeRadiusMeters);
        return;
      }

      final result = await supabase.fetchTrendingHotspotsByDensity(
        latitude: lat,
        longitude: lng,
        forcedRadiusMeters: _forcedRadiusMeters,
        isCancelled: () => !mounted || generation != _loadGeneration,
      );

      if (!mounted || generation != _loadGeneration || result.cancelled) {
        return;
      }

      final spots = result.hotspots;
      setState(() {
        _loading = false;
        _hotspots = spots;
        _center = center;
        _activeRadiusMeters = result.radiusMeters;
        _totalVideos = result.totalVideos;
        _selected = spots.isNotEmpty
            ? spots.firstWhere(
                (spot) => spot.id == _selected?.id,
                orElse: () => spots.first,
              )
            : null;
        _error = null;
      });
      _moveTo(center, result.radiusMeters);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = AppStrings.of(context).trendConnError;
        _hotspots = const [];
        _totalVideos = 0;
      });
    }
  }

  void _moveTo(LatLng center, double radiusMeters) {
    try {
      _mapController.move(center, _zoomForRadius(radiusMeters));
    } catch (_) {
      // Map henüz mount olmamış olabilir.
    }
  }

  static double _zoomForRadius(double meters) {
    if (meters <= 500) return 15.0;
    if (meters <= 1000) return 14.2;
    if (meters <= 2000) return 13.4;
    if (meters <= 3000) return 12.8;
    if (meters <= 5000) return 12.2;
    if (meters <= 10000) return 11.3;
    return 10.4;
  }

  void _onSelect(CampusHotspot spot) {
    setState(() => _selected = spot);
    try {
      _mapController.move(
        LatLng(spot.latitude, spot.longitude),
        _mapController.camera.zoom.clamp(13.5, 16.5),
      );
    } catch (_) {}
  }

  void _selectRadius(double? meters) {
    if (_forcedRadiusMeters == meters && meters != null) return;
    setState(() => _forcedRadiusMeters = meters);
    _load();
  }

  void _openSelected() {
    final spot = _selected;
    if (spot == null) return;
    widget.onHotspotSelected?.call(
      spot.copyWith(vicinityRadiusMeters: _activeRadiusMeters),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // Floating nav at safeBottom+12, ~72–88px tall → ≥16px gap above nav.
    final bottomPad = MediaQuery.paddingOf(context).bottom + 12 + 88 + 16;
    final radiusLabel = s.densityRadiusLabel(_activeRadiusMeters);

    return ColoredBox(
      color: NoolColors.night,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_center != null && !_loading && _error == null)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center!,
                initialZoom: _zoomForRadius(_activeRadiusMeters),
                minZoom: 9.5,
                maxZoom: 18,
                backgroundColor: NoolColors.night,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.nool.app',
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _center!,
                      radius: _activeRadiusMeters,
                      useRadiusInMeter: true,
                      color: NoolColors.acid.withValues(alpha: 0.07),
                      borderColor: NoolColors.acid.withValues(alpha: 0.55),
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final pulse = 0.92 + (_pulse.value * 0.16);
                    return NoolHeatMapLayers(
                      hotspots: _hotspots,
                      selectedId: _selected?.id,
                      onSelect: _onSelect,
                      pulse: pulse,
                    );
                  },
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _center!,
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NoolColors.acid,
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
                    ),
                  ],
                ),
              ],
            )
          else
            const NoolAtmosphere(
              accent: AtmosphereAccent.tangerine,
              intensity: 0.7,
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 200,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      NoolColors.night.withValues(alpha: 0.9),
                      NoolColors.night.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const NoolLogoMark(size: 32, border: true, shadow: true),
                      const SizedBox(width: 10),
                      Text(
                        'NOOL',
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      BrutalPressable(
                        offset: const Offset(2, 2),
                        enabled: !_loading,
                        onTap: _load,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: NoolColors.night,
                            border: Border.all(color: NoolColors.ink, width: 3),
                          ),
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 20,
                            color: _loading
                                ? NoolColors.lavender
                                : NoolColors.acid,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.trendHeadline,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      height: 1.05,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.trendSubWithRadius(radiusLabel),
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DensityRingBar(
                    activeMeters: _activeRadiusMeters,
                    forcedMeters: _forcedRadiusMeters,
                    onSelect: _selectRadius,
                    enabled: !_loading,
                  ),
                ],
              ),
            ),
          ),
          if (_showIntro && !_introDone)
            Positioned.fill(
              child: NoolTrendIntro(
                key: ValueKey('nool-trend-intro-$_introKey'),
                onFinished: _onIntroFinished,
              ),
            )
          else if (_loading)
            const Center(
              child: NoolLottieView.loading(
                width: 64,
                height: 64,
                compact: true,
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _BrutalErrorCard(
                  message: _error!,
                  onRetry: _load,
                ),
              ),
            )
          else ...[
            if (_hotspots.isNotEmpty)
              Positioned(
                right: 16,
                bottom: bottomPad + (_selected != null ? 118 : 16),
                child: _HeatLegend(totalVideos: _totalVideos),
              ),
            if (_selected != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: bottomPad,
                child: _SelectedHotspotCard(
                  spot: _selected!,
                  onOpen: _openSelected,
                ),
              )
            else if (_hotspots.isEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: bottomPad,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: NoolColors.night.withValues(alpha: 0.9),
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
                    s.trendNoHeat,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DensityRingBar extends StatelessWidget {
  const _DensityRingBar({
    required this.activeMeters,
    required this.forcedMeters,
    required this.onSelect,
    required this.enabled,
  });

  final double activeMeters;
  final double? forcedMeters;
  final ValueChanged<double?> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final autoSelected = forcedMeters == null;

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _RingChip(
            label: s.densityAuto,
            selected: autoSelected,
            enabled: enabled,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 6),
          for (final meters in SupabaseConfig.densityRadiiMeters) ...[
            _RingChip(
              label: s.densityRadiusLabel(meters),
              selected: !autoSelected && forcedMeters == meters,
              highlight: autoSelected && activeMeters == meters,
              enabled: enabled,
              onTap: () => onSelect(meters),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _RingChip extends StatelessWidget {
  const _RingChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final bool selected;
  final bool highlight;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? NoolColors.acid : NoolColors.night;
    final fg = selected ? NoolColors.ink : NoolColors.white;
    final border = selected || highlight ? NoolColors.acid : NoolColors.ink;

    return BrutalPressable(
      offset: const Offset(2, 2),
      enabled: enabled,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 2.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.syne(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.totalVideos});

  final int totalVideos;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: NoolColors.night.withValues(alpha: 0.88),
        border: Border.all(color: NoolColors.ink, width: 3),
        boxShadow: const [
          BoxShadow(
            color: NoolColors.ink,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.heat,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.trendVideoCount(totalVideos),
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 88,
            height: 10,
            decoration: BoxDecoration(
              border: Border.all(color: NoolColors.ink, width: 2),
              gradient: const LinearGradient(
                colors: [
                  NoolColors.lavender,
                  NoolColors.acid,
                  NoolColors.tangerine,
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.cold,
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 28),
              Text(
                s.hot,
                style: GoogleFonts.syne(
                  color: NoolColors.tangerine,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectedHotspotCard extends StatelessWidget {
  const _SelectedHotspotCard({
    required this.spot,
    required this.onOpen,
  });

  final CampusHotspot spot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return BrutalPressable(
      offset: const Offset(4, 4),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: BoxDecoration(
          color: NoolColors.night,
          border: Border.all(color: NoolColors.ink, width: 3.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.trendVideoCount(spot.dropCount).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.trendAway(spot.distanceLabel),
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: NoolColors.acid,
                border: Border.all(color: NoolColors.ink, width: 2.5),
              ),
              child: Text(
                s.dropsHere,
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
    );
  }
}

class _BrutalErrorCard extends StatelessWidget {
  const _BrutalErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NoolColors.night,
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
            s.trendStop,
            style: GoogleFonts.syne(
              color: NoolColors.tangerine,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.syne(
              color: NoolColors.lavender,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: NoolColors.acid,
            child: InkWell(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: NoolColors.ink, width: 3),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.trendRetry,
                  style: GoogleFonts.syne(
                    color: NoolColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
