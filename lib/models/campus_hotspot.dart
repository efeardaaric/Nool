/// Kampüs trend kümesi (ısı haritası kartı).
class CampusHotspot {
  const CampusHotspot({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.dropCount,
    required this.distanceMeters,
    this.vicinityRadiusMeters,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int dropCount;
  final double distanceMeters;

  /// Trend’de seçili yoğunluk halkası (metre) — izleme bu halka içinde kalır.
  final double? vicinityRadiusMeters;

  factory CampusHotspot.fromRpc(
    Map<String, dynamic> row, {
    double? vicinityRadiusMeters,
  }) {
    return CampusHotspot(
      id: row['cluster_id']?.toString() ??
          '${row['latitude']}_${row['longitude']}',
      name: (row['name'] as String?) ?? 'Aktif Bölge',
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      dropCount: (row['drop_count'] as num?)?.toInt() ?? 0,
      distanceMeters: (row['distance_m'] as num?)?.toDouble() ?? 0,
      vicinityRadiusMeters: vicinityRadiusMeters,
    );
  }

  CampusHotspot copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    int? dropCount,
    double? distanceMeters,
    double? vicinityRadiusMeters,
  }) {
    return CampusHotspot(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      dropCount: dropCount ?? this.dropCount,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      vicinityRadiusMeters: vicinityRadiusMeters ?? this.vicinityRadiusMeters,
    );
  }

  String get distanceLabel {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()}m';
    }
    final km = distanceMeters / 1000;
    if (km < 10) return '${km.toStringAsFixed(1)}km';
    return '${km.round()}km';
  }

  String get dropsLabel {
    if (dropCount == 1) return '1 video';
    return '$dropCount video';
  }
}

/// Feed’i belirli bir hotspot etrafıyla sınırlamak için.
class HotspotFeedFilter {
  const HotspotFeedFilter({
    required this.latitude,
    required this.longitude,
    required this.name,
    this.radiusMeters = 320,
    this.vicinityRadiusMeters,
  });

  final double latitude;
  final double longitude;
  final String name;

  /// Hotspot kümesi izleme yarıçapı.
  final double radiusMeters;

  /// Kullanıcının aktif yoğunluk halkası — dünya geneli fallback yok.
  final double? vicinityRadiusMeters;
}
