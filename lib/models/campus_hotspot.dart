/// Kampüs trend kümesi (ısı haritası kartı).
class CampusHotspot {
  const CampusHotspot({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.dropCount,
    required this.distanceMeters,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int dropCount;
  final double distanceMeters;

  factory CampusHotspot.fromRpc(Map<String, dynamic> row) {
    return CampusHotspot(
      id: row['cluster_id']?.toString() ??
          '${row['latitude']}_${row['longitude']}',
      name: (row['name'] as String?) ?? 'Aktif Bölge',
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      dropCount: (row['drop_count'] as num?)?.toInt() ?? 0,
      distanceMeters: (row['distance_m'] as num?)?.toDouble() ?? 0,
    );
  }

  String get distanceLabel {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()}m uzakta';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km uzakta';
  }

  String get dropsLabel {
    if (dropCount == 1) return '1 Aktif Video';
    return '$dropCount Drops';
  }
}

/// Feed’i belirli bir hotspot etrafıyla sınırlamak için.
class HotspotFeedFilter {
  const HotspotFeedFilter({
    required this.latitude,
    required this.longitude,
    required this.name,
    this.radiusMeters = 280,
  });

  final double latitude;
  final double longitude;
  final String name;
  final double radiusMeters;
}
