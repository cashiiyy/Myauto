import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart' hide LocationPermission;

/// Centralised permission management.
/// Uses [permission_handler] for the rationale dialog flow and
/// [geolocator] for the actual location check (they work together).
class PermissionService {
  // ── Location service (GPS switch) ────────────────────────────────

  /// Returns true if the device's location hardware is switched on.
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  // ── Permission status helpers ─────────────────────────────────────

  /// True when fine-location permission is granted (or limited on iOS).
  Future<bool> isLocationGranted() async {
    final status = await Permission.location.status;
    return status.isGranted || status.isLimited;
  }

  /// True when background-location permission is granted.
  Future<bool> isBackgroundLocationGranted() async {
    final status = await Permission.locationAlways.status;
    return status.isGranted;
  }

  // ── Request flows ─────────────────────────────────────────────────

  /// Requests fine + coarse location permission.
  /// Returns the resulting [PermissionStatus].
  Future<PermissionStatus> requestLocation() =>
      Permission.location.request();

  /// Requests background (always-on) location.
  /// Must only be called AFTER [requestLocation] is granted — Android requires this order.
  Future<PermissionStatus> requestBackgroundLocation() =>
      Permission.locationAlways.request();

  /// Opens the device app-settings page so the user can manually grant
  /// permissions that were permanently denied.
  Future<bool> openSettings() => openAppSettings();

  // ── Convenience: full flow result ────────────────────────────────

  /// Runs the complete permission check and returns a [LocationPermissionResult].
  Future<LocationPermissionResult> checkAll() async {
    final serviceOn = await isLocationServiceEnabled();
    if (!serviceOn) return LocationPermissionResult.serviceDisabled;

    final locationGranted = await isLocationGranted();
    if (!locationGranted) {
      final status = await Permission.location.status;
      if (status.isPermanentlyDenied) {
        return LocationPermissionResult.permanentlyDenied;
      }
      return LocationPermissionResult.denied;
    }

    return LocationPermissionResult.granted;
  }
}

enum LocationPermissionResult {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
}
