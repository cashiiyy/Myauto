/// Maps the NearbyDriverResponse schema from GET /api/drivers/nearby.
///
/// Phone numbers are deliberately absent — the backend never returns them
/// in this endpoint. Contact is only permitted via the authorized ride flow.
class NearbyDriverModel {
  final String driverUid;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final double? headingDegrees;
  final double? accuracyMeters;

  /// LIVE | DELAYED | STALE
  final String freshness;
  final bool isAvailable;
  final String vehicleType;
  final double? rating;

  const NearbyDriverModel({
    required this.driverUid,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.headingDegrees,
    this.accuracyMeters,
    this.freshness = 'LIVE',
    this.isAvailable = true,
    this.vehicleType = 'auto-rickshaw',
    this.rating,
  });

  factory NearbyDriverModel.fromJson(Map<String, dynamic> json) {
    return NearbyDriverModel(
      driverUid: json['driver_uid'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      headingDegrees: (json['heading_degrees'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
      freshness: json['freshness'] as String? ?? 'LIVE',
      isAvailable: json['is_available'] as bool? ?? true,
      vehicleType: json['vehicle_type'] as String? ?? 'auto-rickshaw',
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }

  /// Create an updated copy from a WebSocket driver.presence event payload.
  NearbyDriverModel copyWithPresenceEvent(Map<String, dynamic> payload) {
    return NearbyDriverModel(
      driverUid: driverUid,
      latitude: (payload['latitude'] as num?)?.toDouble() ?? latitude,
      longitude: (payload['longitude'] as num?)?.toDouble() ?? longitude,
      distanceKm: distanceKm,
      headingDegrees:
          (payload['heading_degrees'] as num?)?.toDouble() ?? headingDegrees,
      accuracyMeters:
          (payload['accuracy_meters'] as num?)?.toDouble() ?? accuracyMeters,
      freshness: payload['freshness'] as String? ?? freshness,
      isAvailable:
          (payload['state'] as String? ?? 'AVAILABLE') == 'AVAILABLE',
      vehicleType: vehicleType,
      rating: rating,
    );
  }

  bool get isStale => freshness == 'STALE' || freshness == 'OFFLINE';

  @override
  String toString() =>
      'NearbyDriverModel(uid=$driverUid, lat=$latitude, lng=$longitude, '
      'dist=${distanceKm.toStringAsFixed(2)}km, freshness=$freshness)';
}
