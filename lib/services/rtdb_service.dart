import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/driver_location_model.dart';
import '../models/ride_request_model.dart';
import '../models/ride_share_model.dart';

/// Pure I/O service wrapping all Firebase Realtime Database operations.
/// No business logic — just reads, writes, and streams.
/// All geospatial filtering is done client-side via Haversine formula.
class RtdbService {
  final FirebaseDatabase _db;

  // RTDB node paths
  static const String _driversNode = 'active_drivers';
  static const String _requestsNode = 'ride_requests';
  static const String _sharesNode = 'ride_shares';

  RtdbService(this._db);

  // ─────────────────────────────────────────────────────────────────
  // DRIVER OPERATIONS
  // ─────────────────────────────────────────────────────────────────

  /// Push (set) a driver's live location to RTDB.
  Future<void> updateDriverLocation(DriverLocationModel model) async {
    await _db.ref('$_driversNode/${model.uid}').set(model.toMap());
  }

  /// Register an onDisconnect handler so the driver is removed
  /// automatically when the client loses its RTDB connection.
  Future<void> registerDriverOnDisconnect(String uid) async {
    await _db.ref('$_driversNode/$uid').onDisconnect().remove();
  }

  /// Manually remove a driver from the active_drivers node (e.g., on logout or going offline).
  Future<void> removeDriver(String uid) async {
    await _db.ref('$_driversNode/$uid').remove();
  }

  // ─────────────────────────────────────────────────────────────────
  // PASSENGER / RIDE REQUEST OPERATIONS
  // ─────────────────────────────────────────────────────────────────

  /// Push a passenger's ride request to RTDB.
  Future<void> pushRideRequest(RideRequestModel model) async {
    await _db.ref('$_requestsNode/${model.uid}').set(model.toMap());
  }

  /// Remove a passenger's ride request (cancel or ride accepted).
  Future<void> removeRideRequest(String uid) async {
    await _db.ref('$_requestsNode/$uid').remove();
  }

  // ─────────────────────────────────────────────────────────────────
  // RIDE SHARE OPERATIONS
  // ─────────────────────────────────────────────────────────────────

  /// Push a co-passenger's share entry to RTDB.
  Future<void> pushRideShare(RideShareModel model) async {
    await _db.ref('$_sharesNode/${model.uid}').set(model.toMap());
  }

  /// Remove a co-passenger's share entry (toggle off).
  Future<void> removeRideShare(String uid) async {
    await _db.ref('$_sharesNode/$uid').remove();
  }

  // ─────────────────────────────────────────────────────────────────
  // STREAMS
  // ─────────────────────────────────────────────────────────────────

  /// Stream all active drivers, filtered to [radiusKm] from [centerLat]/[centerLng].
  Stream<List<DriverLocationModel>> nearbyDriversStream({
    required double centerLat,
    required double centerLng,
    double radiusKm = 2.0,
    String? excludeUid,
  }) {
    return _db.ref(_driversNode).onValue.map((event) {
      final data = event.snapshot.value;
      debugPrint('🟡 [STAGE-C] active_drivers onValue — type: ${data.runtimeType}, isNull: ${data == null}');

      if (data == null) {
        debugPrint('🔴 [STAGE-C] active_drivers is EMPTY in RTDB');
        return <DriverLocationModel>[];
      }

      // Defensive: handle unexpected data shapes gracefully
      if (data is! Map) {
        debugPrint('🔴 [STAGE-C] UNEXPECTED TYPE: ${data.runtimeType} — expected Map. Data: $data');
        return <DriverLocationModel>[];
      }

      final rawMap = data as Map<dynamic, dynamic>;
      final List<DriverLocationModel> result = [];

      for (final entry in rawMap.entries) {
        if (entry.key.toString() == excludeUid) continue;
        try {
          final model = DriverLocationModel.fromMap(
            entry.key.toString(),
            entry.value as Map<dynamic, dynamic>,
          );
          final dist = _haversineKm(
              centerLat, centerLng, model.latitude, model.longitude);
          if (dist <= radiusKm) {
            result.add(model);
          }
        } catch (e) {
          debugPrint('🔴 [STAGE-C] Failed to parse driver ${entry.key}: $e');
        }
      }
      debugPrint('🟢 [STAGE-C] active_drivers: ${rawMap.length} total, ${result.length} within ${radiusKm}km');
      return result;
    });
  }

  /// Stream all active ride requests, filtered to [radiusKm].
  Stream<List<RideRequestModel>> nearbyRideRequestsStream({
    required double centerLat,
    required double centerLng,
    double radiusKm = 3.0,
    String? excludeUid,
  }) {
    return _db.ref(_requestsNode).onValue.map((event) {
      final data = event.snapshot.value;
      debugPrint('🟡 [STAGE-C-REQ] ride_requests onValue — type: ${data.runtimeType}, isNull: ${data == null}');

      if (data == null) return <RideRequestModel>[];

      // Defensive: handle unexpected data shapes gracefully
      if (data is! Map) {
        debugPrint('🔴 [STAGE-C-REQ] UNEXPECTED TYPE: ${data.runtimeType} — expected Map');
        return <RideRequestModel>[];
      }

      final rawMap = data as Map<dynamic, dynamic>;
      final List<RideRequestModel> result = [];

      for (final entry in rawMap.entries) {
        if (entry.key.toString() == excludeUid) continue;
        try {
          final model = RideRequestModel.fromMap(
            entry.key.toString(),
            entry.value as Map<dynamic, dynamic>,
          );
          if (model.status == 'waiting') {
            final dist = _haversineKm(
                centerLat, centerLng, model.latitude, model.longitude);
            if (dist <= radiusKm) {
              result.add(model);
            }
          }
        } catch (e) {
          debugPrint('🔴 [STAGE-C-REQ] Failed to parse request ${entry.key}: $e');
        }
      }
      debugPrint('🟢 [STAGE-C-REQ] ride_requests: ${rawMap.length} total, ${result.length} within ${radiusKm}km');
      return result;
    });
  }

  /// Stream all active ride shares, filtered to [radiusKm].
  Stream<List<RideShareModel>> nearbyRideSharesStream({
    required double centerLat,
    required double centerLng,
    double radiusKm = 2.0,
    String? excludeUid,
  }) {
    return _db.ref(_sharesNode).onValue.map((event) {
      final data = event.snapshot.value;
      debugPrint('🟡 [STAGE-C-SHARE] ride_shares onValue — type: ${data.runtimeType}, isNull: ${data == null}');

      if (data == null) return <RideShareModel>[];

      // Defensive: handle unexpected data shapes gracefully
      if (data is! Map) {
        debugPrint('🔴 [STAGE-C-SHARE] UNEXPECTED TYPE: ${data.runtimeType} — expected Map');
        return <RideShareModel>[];
      }

      final rawMap = data as Map<dynamic, dynamic>;
      final List<RideShareModel> result = [];

      for (final entry in rawMap.entries) {
        if (entry.key.toString() == excludeUid) continue;
        try {
          final model = RideShareModel.fromMap(
            entry.key.toString(),
            entry.value as Map<dynamic, dynamic>,
          );
          final dist = _haversineKm(
              centerLat, centerLng, model.latitude, model.longitude);
          if (dist <= radiusKm) {
            result.add(model);
          }
        } catch (e) {
          debugPrint('🔴 [STAGE-C-SHARE] Failed to parse share ${entry.key}: $e');
        }
      }
      debugPrint('🟢 [STAGE-C-SHARE] ride_shares: ${rawMap.length} total, ${result.length} within ${radiusKm}km');
      return result;
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────

  /// Haversine great-circle distance in kilometres.
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * math.pi / 180;
}
