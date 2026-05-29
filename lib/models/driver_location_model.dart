/// Represents a driver's live location entry in RTDB `active_drivers/{uid}`
class DriverLocationModel {
  final String uid;
  final String name;
  final String phone;
  final String vehicleNumber;
  final double latitude;
  final double longitude;
  final double heading;
  final bool isAvailable;
  final double rating;
  final int updatedAt; // Unix ms timestamp

  const DriverLocationModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.vehicleNumber,
    required this.latitude,
    required this.longitude,
    this.heading = 0.0,
    this.isAvailable = true,
    this.rating = 5.0,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'phone': phone,
        'vehicleNumber': vehicleNumber,
        'latitude': latitude,
        'longitude': longitude,
        'heading': heading,
        'isAvailable': isAvailable,
        'rating': rating,
        'updatedAt': updatedAt,
      };

  factory DriverLocationModel.fromMap(String id, Map<dynamic, dynamic> map) {
    return DriverLocationModel(
      uid: id,
      name: map['name']?.toString() ?? 'Driver',
      phone: map['phone']?.toString() ?? '',
      vehicleNumber: map['vehicleNumber']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      isAvailable: map['isAvailable'] as bool? ?? true,
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      updatedAt: (map['updatedAt'] as int?) ?? 0,
    );
  }

  @override
  String toString() =>
      'DriverLocationModel(uid: $uid, lat: $latitude, lng: $longitude)';
}
