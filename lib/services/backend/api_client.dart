import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../config/app_config.dart';
import '../../models/backend_event.dart';
import '../../models/nearby_driver_model.dart';
import '../../models/ride_result_model.dart';

// ── Typed exceptions ──────────────────────────────────────────────────────────

class BackendUnauthorizedException implements Exception {
  const BackendUnauthorizedException();
  @override
  String toString() => 'BackendUnauthorizedException: Token expired or invalid.';
}

class BackendServerException implements Exception {
  final int statusCode;
  final String message;
  const BackendServerException(this.statusCode, this.message);
  @override
  String toString() => 'BackendServerException($statusCode): $message';
}

class BackendNetworkException implements Exception {
  final String message;
  const BackendNetworkException(this.message);
  @override
  String toString() => 'BackendNetworkException: $message';
}

// ── Location payload ──────────────────────────────────────────────────────────

class LocationPayload {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? altitude;
  final double? speedMps;
  final double? headingDegrees;
  final int capturedAt; // Unix ms — device time, NOT used as authoritative
  final int? sequence;
  final String role; // 'driver' | 'passenger'

  const LocationPayload({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.altitude,
    this.speedMps,
    this.headingDegrees,
    required this.capturedAt,
    this.sequence,
    this.role = 'driver',
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (altitude != null) 'altitude': altitude,
        if (speedMps != null) 'speed_mps': speedMps,
        if (headingDegrees != null) 'heading_degrees': headingDegrees,
        'captured_at': capturedAt,
        if (sequence != null) 'sequence': sequence,
        'role': role,
      };
}

// ── API Client ────────────────────────────────────────────────────────────────

/// Authenticated HTTP client for the MyAuto FastAPI backend.
///
/// - Automatically attaches the current Firebase ID token as `Authorization: Bearer`
/// - Refreshes the token transparently on 401 and retries once
/// - In [AppConfig.mockMode] all writes are no-ops; reads return mock data
class BackendApiClient {
  late final Dio _dio;
  final FirebaseAuth? _auth;

  // Monotonically increasing sequence number for GPS updates
  int _locationSequence = 0;

  BackendApiClient({FirebaseAuth? auth})
      : _auth = auth {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.backendUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(_AuthInterceptor(_auth));
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (o) => debugPrint('[ApiClient] $o'),
    ));
  }

  // ── Health ────────────────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    if (AppConfig.mockMode) return true;
    try {
      final resp = await _dio.get('/health');
      return resp.statusCode == 200 && resp.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ── Location ──────────────────────────────────────────────────────────────

  /// Send a GPS location update to the backend.
  ///
  /// IMPORTANT: coordinates are sent exactly as received from the device.
  /// They are NEVER modified before being sent.
  Future<void> updateLocation(LocationPayload payload) async {
    if (AppConfig.mockMode) {
      debugPrint('[ApiClient] MOCK: updateLocation ${payload.latitude}, ${payload.longitude}');
      return;
    }
    try {
      final body = payload.toJson();
      body['sequence'] = ++_locationSequence;
      await _dio.post('/api/location', data: body);
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  // ── Nearby Drivers ────────────────────────────────────────────────────────

  Future<List<NearbyDriverModel>> getNearbyDrivers(
    double lat,
    double lng, {
    double radiusKm = AppConfig.nearbyDriverRadiusKm,
  }) async {
    if (AppConfig.mockMode) return _mockDrivers(lat, lng);
    try {
      final resp = await _dio.get('/api/drivers/nearby', queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius_km': radiusKm,
      });
      final list = resp.data as List<dynamic>;
      return list
          .map((j) => NearbyDriverModel.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  // ── Ride Requests ─────────────────────────────────────────────────────────

  Future<RideRequestResult> createRideRequest(
    double pickupLat,
    double pickupLng, {
    double? pickupAccuracyMeters,
    double? destinationLat,
    double? destinationLng,
    String? destinationLabel,
    String? driverUid,
    String? passengerName,
    String? idempotencyKey,
    String? correlationId,
    String? notes,
  }) async {
    if (AppConfig.mockMode) {
      return RideRequestResult(
        requestId: 'mock-request-id',
        status: 'matching',
        message: 'Mock: match found.',
        driverUid: driverUid ?? 'mock_driver',
      );
    }
    try {
      final headers = <String, dynamic>{};
      if (idempotencyKey != null) {
        headers['Idempotency-Key'] = idempotencyKey;
      }
      if (correlationId != null) {
        headers['X-Correlation-ID'] = correlationId;
      }

      final body = <String, dynamic>{
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        if (pickupAccuracyMeters != null)
          'pickup_accuracy_meters': pickupAccuracyMeters,
        if (destinationLat != null) 'destination_lat': destinationLat,
        if (destinationLng != null) 'destination_lng': destinationLng,
        if (destinationLabel != null) 'destination_label': destinationLabel,
        if (driverUid != null) 'driver_uid': driverUid,
        if (passengerName != null) 'passenger_name': passengerName,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        if (notes != null) 'notes': notes,
      };

      final resp = await _dio.post(
        '/api/rides/requests',
        data: body,
        options: Options(headers: headers),
      );
      return RideRequestResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  Future<void> cancelRideRequest(String requestId) async {
    if (AppConfig.mockMode) return;
    try {
      await _dio.post('/api/rides/requests/$requestId/cancel');
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  // ── Match Actions ─────────────────────────────────────────────────────────

  Future<MatchActionResult> acceptMatch(String matchId) async {
    if (AppConfig.mockMode) {
      return MatchActionResult(matchId: matchId, status: 'accepted', message: 'Mock accepted');
    }
    try {
      final resp = await _dio.post('/api/matches/$matchId/accept');
      return MatchActionResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  Future<MatchActionResult> rejectMatch(String matchId) async {
    if (AppConfig.mockMode) {
      return MatchActionResult(matchId: matchId, status: 'rejected', message: 'Mock rejected');
    }
    try {
      final resp = await _dio.post('/api/matches/$matchId/reject');
      return MatchActionResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  Future<BackendEvent?> getDriverPendingRide() async {
    if (AppConfig.mockMode) return null;
    try {
      final resp = await _dio.get('/api/rides/driver/pending');
      final data = resp.data as Map<String, dynamic>;
      if (data['has_pending'] == true && data['payload'] != null) {
        debugPrint('[DIAG][ApiClient] Recovered pending ride request from server: ${data['ride_id']}');
        return BackendEvent(
          eventId: 'pending-${data['ride_id']}',
          type: BackendEventType.rideRequested,
          serverTimestamp: DateTime.now().toUtc().toIso8601String(),
          rideId: data['ride_id'] as String?,
          payload: data['payload'] as Map<String, dynamic>,
        );
      }
      return null;
    } on DioException catch (e) {
      debugPrint('[ApiClient] getDriverPendingRide error: $e');
      return null;
    }
  }

  // ── Ride Lifecycle ────────────────────────────────────────────────────────

  Future<void> completeRide(String rideId) async {
    if (AppConfig.mockMode) return;
    try {
      await _dio.post('/api/rides/requests/$rideId/complete');
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  Future<SosResult> triggerSos(
    String rideId, {
    double? latitude,
    double? longitude,
    String? message,
  }) async {
    if (AppConfig.mockMode) {
      return SosResult(
        sosEventId: 'mock-sos-id',
        acknowledged: true,
        message: 'Mock SOS acknowledged.',
      );
    }
    try {
      final resp = await _dio.post('/api/rides/requests/$rideId/sos', data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (message != null) 'message': message,
      });
      return SosResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }

  // ── Error handling ────────────────────────────────────────────────────────

  Never _handleDioException(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      throw BackendNetworkException(e.message ?? 'Network error');
    }
    final statusCode = e.response?.statusCode ?? 0;
    if (statusCode == 401) {
      throw const BackendUnauthorizedException();
    }
    final detail = e.response?.data?['detail'] ?? e.message ?? 'Server error';
    throw BackendServerException(statusCode, detail.toString());
  }

  // ── Mock helpers ──────────────────────────────────────────────────────────

  List<NearbyDriverModel> _mockDrivers(double lat, double lng) => [
        NearbyDriverModel(
          driverUid: 'mock_driver_1',
          latitude: lat + 0.005,
          longitude: lng + 0.003,
          distanceKm: 0.6,
          headingDegrees: 45.0,
          freshness: 'LIVE',
          isAvailable: true,
        ),
        NearbyDriverModel(
          driverUid: 'mock_driver_2',
          latitude: lat - 0.008,
          longitude: lng + 0.006,
          distanceKm: 1.1,
          freshness: 'DELAYED',
          isAvailable: true,
        ),
      ];
}

// ── Auth Interceptor ──────────────────────────────────────────────────────────

/// Injects the Firebase ID token into every request.
/// On 401, refreshes the token and retries once.
class _AuthInterceptor extends Interceptor {
  final FirebaseAuth? _auth;

  _AuthInterceptor(this._auth);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && _auth?.currentUser != null) {
      // Token may have expired — force refresh and retry once
      try {
        final freshToken = await _auth!.currentUser!.getIdToken(true);
        if (freshToken != null) {
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $freshToken';
          final cloned = await Dio().fetch(opts);
          return handler.resolve(cloned);
        }
      } catch (_) {
        // Refresh failed — propagate original error
      }
    }
    handler.next(err);
  }

  Future<String?> _getToken() async {
    try {
      return await _auth?.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }
}
