import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Immutable container representing the current visual state rendered on Google Maps.
@immutable
class GoogleMapState {
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final CameraPosition initialCameraPosition;
  final bool isMapReady;

  const GoogleMapState({
    this.markers = const {},
    this.polylines = const {},
    this.initialCameraPosition = const CameraPosition(
      target: LatLng(8.5241, 76.9366), // Default Trivandrum / Kerala coordinates
      zoom: 15.0,
    ),
    this.isMapReady = false,
  });

  GoogleMapState copyWith({
    Set<Marker>? markers,
    Set<Polyline>? polylines,
    CameraPosition? initialCameraPosition,
    bool? isMapReady,
  }) {
    return GoogleMapState(
      markers: markers ?? this.markers,
      polylines: polylines ?? this.polylines,
      initialCameraPosition: initialCameraPosition ?? this.initialCameraPosition,
      isMapReady: isMapReady ?? this.isMapReady,
    );
  }
}
