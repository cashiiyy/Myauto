import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auto_model.dart';
import '../models/driver_location_model.dart';
import '../models/ride_request_model.dart';
import '../models/ride_share_model.dart';
import '../providers/auth_provider.dart';
import '../services/rtdb_service.dart';
import '../services/driver_location_service.dart';
import 'location_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Core RTDB & Service Providers
// ─────────────────────────────────────────────────────────────────────────────

/// Provides the raw [FirebaseDatabase] instance (null-safe: returns null if
/// Firebase is not yet initialised, so providers degrade to empty lists).
final firebaseDatabaseProvider = Provider<FirebaseDatabase?>((ref) {
  if (Firebase.apps.isNotEmpty) {
    return FirebaseDatabase.instance;
  }
  return null;
});

/// Provides the singleton [RtdbService]. Depends on [firebaseDatabaseProvider].
final rtdbServiceProvider = Provider<RtdbService?>((ref) {
  final db = ref.watch(firebaseDatabaseProvider);
  if (db == null) return null;
  return RtdbService(db);
});

// ─────────────────────────────────────────────────────────────────────────────
// Nearby Drivers Stream  (for PASSENGERS)
// ─────────────────────────────────────────────────────────────────────────────

/// Emits a list of [DriverLocationModel] within 2 km of the current user.
/// Used to populate auto-rickshaw markers on the passenger's map.
final nearbyDriversStreamProvider =
    StreamProvider<List<DriverLocationModel>>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final locationAsync = ref.watch(currentLocationProvider);
  final currentUser = ref.watch(authStateProvider).value;

  final position = locationAsync.value;

  if (rtdb == null || position == null) {
    return Stream.value([]);
  }

  return rtdb.nearbyDriversStream(
    centerLat: position.latitude,
    centerLng: position.longitude,
    radiusKm: 2.0,
    excludeUid: currentUser?.uid, // don't show yourself
  );
});

/// Convenience adapter: converts [nearbyDriversStreamProvider] output into
/// [AutoModel] list so it can be dropped into the existing [autoListStreamProvider]
/// slot in [home_screen.dart] without changing the marker-building code.
final rtdbAutoListStreamProvider = StreamProvider<List<AutoModel>>((ref) {
  final driversAsync = ref.watch(nearbyDriversStreamProvider);
  final drivers = driversAsync.value ?? [];
  return Stream.value(
    drivers
        .map((d) => AutoModel(
              id: d.uid,
              latitude: d.latitude,
              longitude: d.longitude,
              isAvailable: d.isAvailable,
              driverName: d.name,
              phoneNumber: d.phone,
              vehicleNumber: d.vehicleNumber,
              rating: d.rating,
            ))
        .toList(),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Nearby Ride Requests Stream  (for DRIVERS)
// ─────────────────────────────────────────────────────────────────────────────

/// Emits a list of [RideRequestModel] within 3 km of the driver.
/// Drivers see these as passenger markers on their map.
final nearbyRideRequestsStreamProvider =
    StreamProvider<List<RideRequestModel>>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final locationAsync = ref.watch(currentLocationProvider);
  final currentUser = ref.watch(authStateProvider).value;

  final position = locationAsync.value;

  if (rtdb == null || position == null) {
    return Stream.value([]);
  }

  return rtdb.nearbyRideRequestsStream(
    centerLat: position.latitude,
    centerLng: position.longitude,
    radiusKm: 3.0,
    excludeUid: currentUser?.uid,
  );
});

/// Convenience adapter: converts [nearbyRideRequestsStreamProvider] to
/// [AutoModel] list for the driver's marker layer.
final rtdbPassengerListStreamProvider = StreamProvider<List<AutoModel>>((ref) {
  final requestsAsync = ref.watch(nearbyRideRequestsStreamProvider);
  final requests = requestsAsync.value ?? [];
  return Stream.value(
    requests
        .map((r) => AutoModel(
              id: r.uid,
              latitude: r.latitude,
              longitude: r.longitude,
              isAvailable: true,
              driverName: r.name,
              phoneNumber: r.phone,
              vehicleNumber: 'N/A',
              rating: 5.0,
            ))
        .toList(),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Nearby Ride Shares Stream  (for CO-PASSENGERS)
// ─────────────────────────────────────────────────────────────────────────────

/// Emits a list of [RideShareModel] within 2 km of the current user.
/// Used so passengers can see nearby co-passengers for ride-splitting.
final nearbyRideSharesStreamProvider =
    StreamProvider<List<RideShareModel>>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final locationAsync = ref.watch(currentLocationProvider);
  final currentUser = ref.watch(authStateProvider).value;

  final position = locationAsync.value;

  if (rtdb == null || position == null) {
    return Stream.value([]);
  }

  return rtdb.nearbyRideSharesStream(
    centerLat: position.latitude,
    centerLng: position.longitude,
    radiusKm: 2.0,
    excludeUid: currentUser?.uid,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Driver Location Service Provider  (for DRIVERS)
// ─────────────────────────────────────────────────────────────────────────────

/// Manages the [DriverLocationService] lifecycle.
/// Only active when a driver user is logged in AND has RTDB available.
/// The provider's `dispose` cleanly stops the timer.
final driverLocationServiceProvider = StateNotifierProvider.autoDispose<
    DriverLocationService, DriverServiceState>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final currentUser = ref.watch(currentUserProvider).value;

  if (rtdb == null || currentUser == null || currentUser.role != 'driver') {
    // Return a no-op placeholder when not applicable
    throw UnimplementedError(
        'driverLocationServiceProvider requires a logged-in driver and RTDB.');
  }

  return DriverLocationService(rtdb, currentUser);
});
