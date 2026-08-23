import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

final locationServiceProvider = Provider((ref) => LocationService());

/// Continuous GPS position stream.
///
/// The stream uses a 10-metre distance filter so it doesn't fire constantly.
/// Only the initial position is fetched eagerly; subsequent updates are
/// driven by device movement.
///
/// NOTE: Firestore GPS sync has been removed — Firestore profile data is
/// written only on explicit profile updates, not on every GPS tick.
final currentLocationProvider = StreamProvider<Position?>((ref) async* {
  final locationService = ref.watch(locationServiceProvider);

  // 1. Emit initial position immediately so the map has a center
  final initialPos = await locationService.getCurrentLocation();
  if (initialPos != null) {
    debugPrint(
        '📍 [Location] Initial: ${initialPos.latitude}, ${initialPos.longitude}');
    yield initialPos;
  } else {
    debugPrint('📍 [Location] Initial position unavailable');
    yield null;
  }

  // 2. Continuous stream driven by movement (10m filter)
  try {
    await for (final position in Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    )) {
      yield position;
    }
  } catch (e) {
    debugPrint('📍 [Location] Stream error: $e');
  }
});

// ── Stable Center Provider ────────────────────────────────────────────────────
//
// Only updates when the user moves >500m from the last-known center.
// Prevents stream invalidation loops that would destroy and re-create
// RTDB / backend listeners on every GPS tick.

class _StableCenterNotifier extends StateNotifier<Position?> {
  _StableCenterNotifier(Ref ref) : super(null) {
    ref.listen<AsyncValue<Position?>>(currentLocationProvider, (prev, next) {
      final newPos = next.valueOrNull;
      if (newPos == null) return;

      if (state == null) {
        debugPrint(
            '📌 [StableCenter] First center: ${newPos.latitude}, ${newPos.longitude}');
        state = newPos;
        return;
      }

      final dist = Geolocator.distanceBetween(
        state!.latitude,
        state!.longitude,
        newPos.latitude,
        newPos.longitude,
      );
      if (dist > 500) {
        debugPrint(
            '📌 [StableCenter] Re-centered (moved ${dist.toStringAsFixed(0)}m)');
        state = newPos;
      }
    });
  }
}

final stableCenterProvider =
    StateNotifierProvider<_StableCenterNotifier, Position?>((ref) {
  return _StableCenterNotifier(ref);
});
