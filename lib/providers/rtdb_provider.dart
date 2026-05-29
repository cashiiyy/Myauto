import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/driver_location_model.dart';
import '../models/ride_request_model.dart';
import '../models/ride_share_model.dart';
import '../providers/auth_provider.dart';
import '../services/rtdb_service.dart';
import 'location_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Core RTDB & Service Providers
// ─────────────────────────────────────────────────────────────────────────────

/// Provides the FirebaseDatabase instance with an explicit URL so the correct
/// RTDB region is always used regardless of google-services.json defaults.
final firebaseDatabaseProvider = Provider<FirebaseDatabase?>((ref) {
  if (Firebase.apps.isEmpty) return null;
  return FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://myauto-493fc-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
});

/// Provides the singleton [RtdbService].
final rtdbServiceProvider = Provider<RtdbService?>((ref) {
  final db = ref.watch(firebaseDatabaseProvider);
  if (db == null) return null;
  return RtdbService(db);
});

// ─────────────────────────────────────────────────────────────────────────────
// Stream Providers — raw RTDB streams (used directly in HomeScreen markers)
//
// FIX: These now watch stableCenterProvider (updates only when user moves
// >500m) instead of currentLocationProvider (updates every 10m GPS tick).
// This prevents the stream invalidation loop that was destroying markers.
// ─────────────────────────────────────────────────────────────────────────────

/// Streams nearby active drivers for PASSENGERS (2 km radius).
/// Re-emits every time the RTDB node changes — no adapter/double-wrap.
final nearbyDriversStreamProvider =
    StreamProvider<List<DriverLocationModel>>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final position = ref.watch(stableCenterProvider); // ← FIX: was currentLocationProvider
  final uid = ref.watch(authStateProvider).value?.uid;

  debugPrint('🟡 [STAGE-B] nearbyDriversStream EVALUATED — rtdb=${rtdb != null}, pos=$position, uid=$uid');

  if (rtdb == null || position == null) {
    debugPrint('🔴 [STAGE-B] BAILING — rtdb=${rtdb != null}, position=$position');
    return const Stream.empty();
  }

  debugPrint('🟢 [STAGE-B] Subscribing to active_drivers at (${position.latitude}, ${position.longitude})');
  return rtdb.nearbyDriversStream(
    centerLat: position.latitude,
    centerLng: position.longitude,
    radiusKm: 2.0,
    excludeUid: uid,
  );
});

/// Streams nearby ride requests for DRIVERS (3 km radius).
final nearbyRideRequestsStreamProvider =
    StreamProvider<List<RideRequestModel>>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final position = ref.watch(stableCenterProvider); // ← FIX: was currentLocationProvider
  final uid = ref.watch(authStateProvider).value?.uid;

  debugPrint('🟡 [STAGE-B-REQ] nearbyRideRequestsStream EVALUATED — rtdb=${rtdb != null}, pos=$position, uid=$uid');

  if (rtdb == null || position == null) {
    debugPrint('🔴 [STAGE-B-REQ] BAILING — rtdb=${rtdb != null}, position=$position');
    return const Stream.empty();
  }

  debugPrint('🟢 [STAGE-B-REQ] Subscribing to ride_requests at (${position.latitude}, ${position.longitude})');
  return rtdb.nearbyRideRequestsStream(
    centerLat: position.latitude,
    centerLng: position.longitude,
    radiusKm: 3.0,
    excludeUid: uid,
  );
});

/// Streams nearby ride-share co-passengers for EVERYONE (2 km radius).
final nearbyRideSharesStreamProvider =
    StreamProvider<List<RideShareModel>>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final position = ref.watch(stableCenterProvider); // ← FIX: was currentLocationProvider
  final uid = ref.watch(authStateProvider).value?.uid;

  debugPrint('🟡 [STAGE-B-SHARE] nearbyRideSharesStream EVALUATED — rtdb=${rtdb != null}, pos=$position, uid=$uid');

  if (rtdb == null || position == null) {
    debugPrint('🔴 [STAGE-B-SHARE] BAILING — rtdb=${rtdb != null}, position=$position');
    return const Stream.empty();
  }

  debugPrint('🟢 [STAGE-B-SHARE] Subscribing to ride_shares at (${position.latitude}, ${position.longitude})');
  return rtdb.nearbyRideSharesStream(
    centerLat: position.latitude,
    centerLng: position.longitude,
    radiusKm: 2.0,
    excludeUid: uid,
  );
});
