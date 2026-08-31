import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../config/app_config.dart';

// ── Result model ──────────────────────────────────────────────────────────────

/// The result of a routing request — polyline, distance, and ETA.
class RouteResult {
  /// Decoded route polyline as a list of [LatLng] points.
  final List<LatLng> polyline;

  /// Total route distance in kilometres.
  final double distanceKm;

  /// Estimated travel time in seconds.
  final int durationSeconds;

  /// Human-readable ETA string (e.g. "12 min").
  String get etaLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 1) return '< 1 min';
    return '$minutes min';
  }

  const RouteResult({
    required this.polyline,
    required this.distanceKm,
    required this.durationSeconds,
  });
}

// ── Abstract interface ────────────────────────────────────────────────────────

/// Interface for route / ETA calculation.
///
/// Implementations:
/// - [ValhallaRoutingService] — real routing via Valhalla
/// - [MockRoutingService]     — fixed mock route for testing
///
/// The routing service does NOT initiate bookings, change driver state,
/// or alter fare/distance display logic. It is a pure calculation service.
abstract class RoutingService {
  /// Calculate a route from [from] to [to].
  /// Returns null if routing fails or is unavailable.
  Future<RouteResult?> getRoute(LatLng from, LatLng to);

  /// Dispose any resources.
  void dispose();
}

// ── Valhalla implementation ───────────────────────────────────────────────────

/// Valhalla routing service adapter.
///
/// Uses the Valhalla `/route` endpoint with the `auto` costing model.
/// For auto-rickshaw specifics, `motorcycle` or `auto` costing is appropriate.
///
/// Endpoint: GET/POST [AppConfig.valhallaUrl]/route
class ValhallaRoutingService implements RoutingService {
  late final Dio _dio;

  ValhallaRoutingService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.valhallaUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (o) => debugPrint('[Valhalla] $o'),
      ));
    }
  }

  @override
  Future<RouteResult?> getRoute(LatLng from, LatLng to) async {
    try {
      final body = {
        'locations': [
          {'lon': from.longitude, 'lat': from.latitude},
          {'lon': to.longitude, 'lat': to.latitude},
        ],
        'costing': AppConfig.valhallaCosting,
        'directions_options': {'units': 'kilometres'},
      };

      final resp = await _dio.post('/route', data: body);
      return _parseResponse(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint('[Valhalla] Routing failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[Valhalla] Unexpected error: $e');
      return null;
    }
  }

  RouteResult? _parseResponse(Map<String, dynamic> data) {
    try {
      final trip = data['trip'] as Map<String, dynamic>?;
      if (trip == null) return null;

      final summary = trip['summary'] as Map<String, dynamic>?;
      final legs = trip['legs'] as List<dynamic>?;

      final distanceKm = (summary?['length'] as num?)?.toDouble() ?? 0.0;
      final durationSec = ((summary?['time'] as num?)?.toDouble() ?? 0.0).toInt();

      // Decode the encoded polyline from the first leg
      final polyline = <LatLng>[];
      if (legs != null && legs.isNotEmpty) {
        final firstLeg = legs.first as Map<String, dynamic>;
        final encoded = firstLeg['shape'] as String?;
        if (encoded != null) {
          polyline.addAll(_decodePolyline(encoded));
        }
      }

      return RouteResult(
        polyline: polyline,
        distanceKm: distanceKm,
        durationSeconds: durationSec,
      );
    } catch (e) {
      debugPrint('[Valhalla] Parse error: $e');
      return null;
    }
  }

  /// Decode a Google-format encoded polyline (precision 6, used by Valhalla).
  List<LatLng> _decodePolyline(String encoded) {
    const factor = 1e6; // Valhalla uses precision 6
    final result = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      // Decode latitude
      int b;
      int shift = 0;
      int result2 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result2 |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result2 & 1) != 0 ? ~(result2 >> 1) : result2 >> 1;
      lat += dLat;

      // Decode longitude
      shift = 0;
      result2 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result2 |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result2 & 1) != 0 ? ~(result2 >> 1) : result2 >> 1;
      lng += dLng;

      result.add(LatLng(lat / factor, lng / factor));
    }
    return result;
  }

  @override
  void dispose() => _dio.close();
}

// ── Mock implementation ───────────────────────────────────────────────────────

/// Returns a fixed straight-line mock route between two points.
/// Used in mock mode and when Valhalla is unavailable.
class MockRoutingService implements RoutingService {
  @override
  Future<RouteResult?> getRoute(LatLng from, LatLng to) async {
    // Approximate straight-line distance using Haversine
    const R = 6371.0;
    final dLat = _toRad(to.latitude - from.latitude);
    final dLng = _toRad(to.longitude - from.longitude);
    final a = _sin2(dLat / 2) +
        _cos(_toRad(from.latitude)) * _cos(_toRad(to.latitude)) * _sin2(dLng / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    final distKm = R * c;

    // Estimate 30 km/h average for auto-rickshaw
    final durationSec = ((distKm / 30) * 3600).toInt();

    // Simple 3-point polyline: from → midpoint → to
    final mid = LatLng(
      (from.latitude + to.latitude) / 2,
      (from.longitude + to.longitude) / 2,
    );

    return RouteResult(
      polyline: [from, mid, to],
      distanceKm: distKm,
      durationSeconds: durationSec,
    );
  }

  @override
  void dispose() {}

  double _toRad(double deg) => deg * 3.141592653589793 / 180;
  double _sin2(double x) => _sin(x) * _sin(x);
  double _sin(double x) {
    // Simple sin approximation for small values
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }
  double _cos(double x) => 1 - (x * x) / 2 + (x * x * x * x) / 24;
  double _sqrt(double x) => x <= 0 ? 0 : x * (1 - (x - 1) / 2); // Newton approx
  double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }
  double _atan(double x) => x - (x * x * x) / 3 + (x * x * x * x * x) / 5;
}

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create the appropriate [RoutingService] based on current config.
RoutingService createRoutingService() {
  if (AppConfig.mockMode) return MockRoutingService();
  return ValhallaRoutingService();
}
