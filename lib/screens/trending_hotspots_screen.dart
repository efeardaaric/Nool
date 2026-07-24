import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/campus_hotspot.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';

/// Kampüs trend / ısı haritası listesi (5 km kümeleme).
class TrendingHotspotsScreen extends StatefulWidget {
  const TrendingHotspotsScreen({
    super.key,
    this.isActive = true,
    this.onHotspotSelected,
  });

  /// Sekme görünürken yenilemek için.
  final bool isActive;

  /// Kart tıklanınca feed filtresi + sekme geçişi.
  final ValueChanged<CampusHotspot>? onHotspotSelected;

  @override
  State<TrendingHotspotsScreen> createState() => _TrendingHotspotsScreenState();
}

class _TrendingHotspotsScreenState extends State<TrendingHotspotsScreen> {
  List<CampusHotspot> _hotspots = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant TrendingHotspotsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
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
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error =
              'GPS çekmiyor — kampüsteki kaos dindi...\nKonumu açıp yenile.';
          _hotspots = const [];
        });
        return;
      }

      if (!supabase.isReady) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _hotspots = _demoHotspots(lat, lng);
          _error = null;
        });
        return;
      }

      final remote = await supabase.fetchTrendingHotspots(
        latitude: lat,
        longitude: lng,
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _hotspots = remote.isEmpty ? _demoHotspots(lat, lng) : remote;
        _error = remote.isEmpty
            ? null
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Bağlantı koptu, kampüsteki kaos dindi...\nWi-Fi’yi dürtüp tekrar dene.';
        _hotspots = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom + 96;

    return NoolAtmosphere(
      accent: AtmosphereAccent.tangerine,
      intensity: 0.85,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: NoolColors.acid,
          backgroundColor: NoolColors.night,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NoolPulse(
                        min: 0.98,
                        max: 1.02,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const NoolLogoMark(
                              size: 36,
                              border: true,
                              shadow: true,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'NOOL',
                              style: GoogleFonts.syne(
                                color: NoolColors.acid,
                                fontWeight: FontWeight.w800,
                                fontSize: 28,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'KAMPÜSTE ŞU AN\nNOOLUYOR?',
                        style: GoogleFonts.syne(
                          color: NoolColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          height: 1.05,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '5 km içindeki aktif drop kümeleri — en sıcak pinler üstte.',
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 36),
                    child: Center(
                      child: Column(
                        children: [
                          NoolLottieView.fire(width: 96, height: 96),
                          SizedBox(height: 8),
                          NoolLottieView.loading(
                            width: 56,
                            height: 56,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_error != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
                  sliver: SliverToBoxAdapter(
                    child: _BrutalErrorCard(message: _error!, onRetry: _load),
                  ),
                )
              else if (_hotspots.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
                  sliver: SliverToBoxAdapter(
                    child: _BrutalErrorCard(
                      message:
                          'Bağlantı koptu, kampüsteki kaos dindi...\nHenüz kimse drop bırakmamış.',
                      onRetry: _load,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
                  sliver: SliverList.separated(
                    itemCount: _hotspots.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final spot = _hotspots[index];
                      return _HotspotCard(
                        spot: spot,
                        onTap: () => widget.onHotspotSelected?.call(spot),
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

class _HotspotCard extends StatelessWidget {
  const _HotspotCard({required this.spot, required this.onTap});

  final CampusHotspot spot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrutalPressable(
      offset: const Offset(3, 3),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: const Color(0xD90D0A1C),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: NoolColors.ink, width: 3),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                spot.distanceLabel,
                style: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name.toUpperCase(),
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dokun → sadece buradaki drop’lar',
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: NoolColors.acid,
                border: Border.all(color: NoolColors.ink, width: 2.5),
              ),
              child: Text(
                spot.dropsLabel,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DUR.',
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
                  'Yeniden yokla',
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

List<CampusHotspot> _demoHotspots(double lat, double lng) {
  return [
    CampusHotspot(
      id: 'd1',
      name: 'Hazırlık Binası',
      latitude: lat + 0.0012,
      longitude: lng + 0.0004,
      dropCount: 42,
      distanceMeters: 150,
    ),
    CampusHotspot(
      id: 'd2',
      name: 'Şenlik Alanı',
      latitude: lat + 0.002,
      longitude: lng - 0.0008,
      dropCount: 28,
      distanceMeters: 320,
    ),
    CampusHotspot(
      id: 'd3',
      name: 'Merkez Kütüphane',
      latitude: lat - 0.0009,
      longitude: lng + 0.0015,
      dropCount: 18,
      distanceMeters: 480,
    ),
    CampusHotspot(
      id: 'd4',
      name: 'Kantinci Önü',
      latitude: lat + 0.003,
      longitude: lng + 0.002,
      dropCount: 9,
      distanceMeters: 890,
    ),
  ];
}
