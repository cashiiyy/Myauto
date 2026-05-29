/// Represents a passenger's ride request entry in RTDB `ride_requests/{uid}`
class RideRequestModel {
  final String uid;
  final String name;
  final String phone;
  final double latitude;
  final double longitude;
  /// 'waiting' | 'accepted' | 'cancelled'
  final String status;
  final int createdAt; // Unix ms timestamp

  const RideRequestModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.latitude,
    required this.longitude,
    this.status = 'waiting',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'phone': phone,
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
        'createdAt': createdAt,
      };

  factory RideRequestModel.fromMap(String id, Map<dynamic, dynamic> map) {
    return RideRequestModel(
      uid: id,
      name: map['name']?.toString() ?? 'Passenger',
      phone: map['phone']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      status: map['status']?.toString() ?? 'waiting',
      createdAt: (map['createdAt'] as int?) ?? 0,
    );
  }

  @override
  String toString() =>
      'RideRequestModel(uid: $uid, status: $status, lat: $latitude, lng: $longitude)';
}
