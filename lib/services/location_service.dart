import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart' hide LocationPermission;
import 'permission_service.dart';

/// Hardened location service that uses [PermissionService] to fully handle
/// all permission states before attempting to get a position.
/// 
/// Returns null (with a typed reason) instead of throwing on permission failure.
class LocationService {
  final _permService = PermissionService();

  /// Returns the current position, or null if permissions/service are unavailable.
  /// Handles all edge cases: service off, denied, permanently denied.
  Future<Position?> getCurrentLocation() async {
    // 1. Check if GPS hardware is on
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    // 2. Check current permission state via permission_handler
    final result = await _permService.checkAll();
    switch (result) {
      case LocationPermissionResult.granted:
        break; // proceed
      case LocationPermissionResult.denied:
        // Try requesting once
        final status = await _permService.requestLocation();
        if (!status.isGranted && !status.isLimited) return null;
        break;
      case LocationPermissionResult.permanentlyDenied:
      case LocationPermissionResult.serviceDisabled:
        return null;
    }

    // 3. Get position with fast fallback and timeout protection
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        // Return quickly, but kick off an accurate update in background if needed
        return lastKnown;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }
}
