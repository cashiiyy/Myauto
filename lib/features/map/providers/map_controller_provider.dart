import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Types of camera commands supported by the map camera intent architecture.
enum CameraRequestType {
  animateTo,
  moveTo,
  fitBounds,
}

/// Represents an abstract camera intent dispatched from application UI to the map.
///
/// **LIFECYCLE SAFETY RULE**:
/// Neither this class nor Riverpod holds a reference to [GoogleMapController].
/// The [MyAutoGoogleMap] widget owns the native controller, listens to this intent,
/// executes it on its local controller, and clears the intent after execution.
@immutable
class CameraRequest {
  final CameraRequestType type;
  final LatLng? target;
  final double zoom;
  final LatLngBounds? bounds;
  final double padding;
  final DateTime timestamp;

  const CameraRequest._({
    required this.type,
    this.target,
    this.zoom = 15.0,
    this.bounds,
    this.padding = 50.0,
    required this.timestamp,
  });

  /// Request a smooth animated camera movement to [target] at [zoom].
  factory CameraRequest.animateTo(LatLng target, {double zoom = 15.0}) {
    return CameraRequest._(
      type: CameraRequestType.animateTo,
      target: target,
      zoom: zoom,
      timestamp: DateTime.now(),
    );
  }

  /// Request an immediate camera cut to [target] at [zoom].
  factory CameraRequest.moveTo(LatLng target, {double zoom = 15.0}) {
    return CameraRequest._(
      type: CameraRequestType.moveTo,
      target: target,
      zoom: zoom,
      timestamp: DateTime.now(),
    );
  }

  /// Request camera bounds fitting for [bounds] with [padding] pixels.
  factory CameraRequest.fitBounds(LatLngBounds bounds, {double padding = 50.0}) {
    return CameraRequest._(
      type: CameraRequestType.fitBounds,
      bounds: bounds,
      padding: padding,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() => 'CameraRequest(type: $type, target: $target, zoom: $zoom, bounds: $bounds)';
}

/// Holds the currently requested camera intent.
///
/// Set by UI components (e.g. Locate-Me FAB, Refresh button, Route bounds calculation).
/// Consumed and cleared exclusively by [MyAutoGoogleMap].
final cameraIntentProvider = StateProvider<CameraRequest?>((ref) => null);

/// Tracks whether the user has manually panned or dragged the map away from their location.
/// When true, the dedicated Recenter button activates and slides into view.
final mapPannedAwayProvider = StateProvider<bool>((ref) => false);

