import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import 'auth_provider.dart';

final locationServiceProvider = Provider((ref) => LocationService());

// A StreamProvider that listens to location changes and updates Firestore automatically
final currentLocationProvider = StreamProvider<Position?>((ref) async* {
  final locationService = ref.watch(locationServiceProvider);
  final user = ref.watch(authStateProvider).value;
  final firestore = ref.watch(firestoreProvider);

  // First, get an initial position so the UI renders quickly
  final initialPos = await locationService.getCurrentLocation();
  if (initialPos != null) {
    debugPrint('📍 [LocationProvider] Initial position: ${initialPos.latitude}, ${initialPos.longitude}');
    yield initialPos;
  } else {
    debugPrint('📍 [LocationProvider] Initial position is NULL — GPS unavailable');
  }

  // Then start listening to continuous updates
  await for (final position in Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // only update if they moved 10 meters
    ),
  )) {
    yield position;
    
    // Background sync to Firestore if user is authenticated
    if (user != null && firestore != null) {
      firestore.collection('users').doc(user.uid).update({
        'latitude': position.latitude,
        'longitude': position.longitude,
      }).catchError((e) {
        // Silently catch errors if the document doesn't exist yet during signup
      });
    }
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Stable Center Provider
// ─────────────────────────────────────────────────────────────────────────────
// 
// This provider only updates when the user moves more than 500m from the
// last-known center. RTDB StreamProviders watch THIS instead of
// currentLocationProvider, preventing the stream invalidation loop where
// every 10m GPS tick would destroy and re-create all Firebase listeners.
//
// BUG FIX: Without this, markers would flicker/vanish because Riverpod
// re-evaluates StreamProviders when any watched dependency changes.
// ─────────────────────────────────────────────────────────────────────────────

class _StableCenterNotifier extends StateNotifier<Position?> {
  _StableCenterNotifier(Ref ref) : super(null) {
    ref.listen<AsyncValue<Position?>>(currentLocationProvider, (prev, next) {
      final newPos = next.valueOrNull;
      if (newPos == null) return;

      // First valid position — set immediately
      if (state == null) {
        debugPrint('📌 [StableCenter] First center set: ${newPos.latitude}, ${newPos.longitude}');
        state = newPos;
        return;
      }

      // Only update if moved > 500m to prevent stream invalidation
      final dist = Geolocator.distanceBetween(
        state!.latitude, state!.longitude,
        newPos.latitude, newPos.longitude,
      );
      if (dist > 500) {
        debugPrint('📌 [StableCenter] Re-centered (moved ${dist.toStringAsFixed(0)}m)');
        state = newPos;
      }
    });
  }
}

final stableCenterProvider =
    StateNotifierProvider<_StableCenterNotifier, Position?>((ref) {
  return _StableCenterNotifier(ref);
});
