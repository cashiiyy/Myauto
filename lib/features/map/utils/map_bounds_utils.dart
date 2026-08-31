import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Calculates a [LatLngBounds] bounding box containing all provided [points].
///
/// Returns null if [points] is empty.
/// If [points] contains a single point or all points are identical,
/// a non-zero minimal delta is applied so [LatLngBounds] has non-zero area.
LatLngBounds? boundsFromPoints(List<LatLng> points) {
  if (points.isEmpty) return null;

  double minLat = points.first.latitude;
  double maxLat = points.first.latitude;
  double minLng = points.first.longitude;
  double maxLng = points.first.longitude;

  for (final p in points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }

  // Google Maps LatLngBounds requires southwest <= northeast.
  // If min and max are equal, apply a slight delta (approx 100m) so bounds can fit.
  if (minLat == maxLat) {
    minLat -= 0.001;
    maxLat += 0.001;
  }
  if (minLng == maxLng) {
    minLng -= 0.001;
    maxLng += 0.001;
  }

  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}
