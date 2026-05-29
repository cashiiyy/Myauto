import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auto_model.dart';
import 'auth_provider.dart'; // uses firestoreProvider from here
import 'rtdb_provider.dart'; // uses RTDB-based stream providers

/// Legacy Firestore-based driver list stream.
/// Still used as a fallback or when RTDB is unavailable.
/// For real-time location, prefer [rtdbAutoListStreamProvider].
final autoListStreamProvider = StreamProvider<List<AutoModel>>((ref) {
  final firestore = ref.watch(firestoreProvider);

  if (firestore == null) {
    // Return mock data for UI testing when Firebase is not configured (e.g., on Web)
    return Stream.value([
      AutoModel(id: 'mock_1', latitude: 8.5241, longitude: 76.9366, isAvailable: true, driverName: 'Mock Driver A', phoneNumber: '123', vehicleNumber: 'KL-01-MOCK', rating: 4.8),
      AutoModel(id: 'mock_2', latitude: 8.5300, longitude: 76.9400, isAvailable: true, driverName: 'Mock Driver B', phoneNumber: '456', vehicleNumber: 'KL-02-TEST', rating: 4.5),
    ]);
  }

  return firestore
    .collection('users')
    .where('role', isEqualTo: 'driver')
    .where('isAvailable', isEqualTo: true)
    .snapshots()
    .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return AutoModel(
          id: doc.id,
          latitude: data['latitude']?.toDouble() ?? 0.0,
          longitude: data['longitude']?.toDouble() ?? 0.0,
          isAvailable: data['isAvailable'] ?? false,
          driverName: data['name'] ?? 'Driver',
          phoneNumber: data['phone'] ?? '',
          vehicleNumber: data['autoRegistrationNumber'] ?? '',
          rating: 5.0,
        );
      }).toList();
  });
});

/// Legacy Firestore-based active passenger list.
/// For real-time RTDB-based passenger requests, prefer [rtdbPassengerListStreamProvider].
final activePassengerListStreamProvider = StreamProvider<List<AutoModel>>((ref) {
  final firestore = ref.watch(firestoreProvider);

  if (firestore == null) {
    return Stream.value([]);
  }

  return firestore
    .collection('users')
    .where('role', isEqualTo: 'passenger')
    .where('isRequesting', isEqualTo: true)
    .snapshots()
    .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return AutoModel(
          id: doc.id,
          latitude: data['latitude']?.toDouble() ?? 0.0,
          longitude: data['longitude']?.toDouble() ?? 0.0,
          isAvailable: true,
          driverName: data['name'] ?? 'Passenger',
          phoneNumber: data['phone'] ?? '',
          vehicleNumber: 'N/A',
          rating: 5.0,
        );
      }).toList();
  });
});
