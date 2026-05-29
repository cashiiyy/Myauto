/// Represents a co-passenger's entry in RTDB `ride_shares/{uid}`
class RideShareModel {
  final String uid;
  final String name;
  final String phone;
  final double latitude;
  final double longitude;
  final double? destLatitude;
  final double? destLongitude;
  final int seatsAvailable;
  final int createdAt; // Unix ms timestamp

  const RideShareModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.latitude,
    required this.longitude,
    this.destLatitude,
    this.destLongitude,
    this.seatsAvailable = 1,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'uid': uid,
      'name': name,
      'phone': phone,
      'latitude': latitude,
      'longitude': longitude,
      'seatsAvailable': seatsAvailable,
      'createdAt': createdAt,
    };
    if (destLatitude != null) map['destLatitude'] = destLatitude;
    if (destLongitude != null) map['destLongitude'] = destLongitude;
    return map;
  }

  factory RideShareModel.fromMap(String id, Map<dynamic, dynamic> map) {
    return RideShareModel(
      uid: id,
      name: map['name']?.toString() ?? 'Co-Passenger',
      phone: map['phone']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      destLatitude: (map['destLatitude'] as num?)?.toDouble(),
      destLongitude: (map['destLongitude'] as num?)?.toDouble(),
      seatsAvailable: (map['seatsAvailable'] as int?) ?? 1,
      createdAt: (map['createdAt'] as int?) ?? 0,
    );
  }

  @override
  String toString() =>
      'RideShareModel(uid: $uid, lat: $latitude, lng: $longitude, seats: $seatsAvailable)';
}
