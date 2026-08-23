import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ride_share_model.dart';
import '../models/ride_result_model.dart';
import '../models/backend_event.dart';
import '../providers/auth_provider.dart';
import '../providers/backend_client_provider.dart';
import '../providers/location_provider.dart';
import '../providers/rtdb_provider.dart';
import '../services/backend/api_client.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum RideActionStatus { idle, requesting, sharing, loading, error }

class RideActionState {
  final RideActionStatus status;
  final String? message;

  /// Server-assigned ride/request UUID.
  final String? backendRequestId;

  /// Driver UID confirmed by the server (ride.matched event).
  final String? matchedDriverUid;

  /// Match ID used for accept/reject calls.
  final String? matchId;

  const RideActionState({
    this.status = RideActionStatus.idle,
    this.message,
    this.backendRequestId,
    this.matchedDriverUid,
    this.matchId,
  });

  bool get isRequesting => status == RideActionStatus.requesting;
  bool get isSharing => status == RideActionStatus.sharing;

  RideActionState copyWith({
    RideActionStatus? status,
    String? message,
    String? backendRequestId,
    String? matchedDriverUid,
    String? matchId,
  }) =>
      RideActionState(
        status: status ?? this.status,
        message: message ?? this.message,
        backendRequestId: backendRequestId ?? this.backendRequestId,
        matchedDriverUid: matchedDriverUid ?? this.matchedDriverUid,
        matchId: matchId ?? this.matchId,
      );
}

// ── Controller ────────────────────────────────────────────────────────────────

/// Manages all passenger and driver ride interactions.
///
/// This is the BACKEND-PRIMARY implementation — all mobility state goes through
/// the FastAPI backend. RTDB is kept only for ride-share entries (temporary).
class RideActionController extends StateNotifier<RideActionState> {
  final Ref _ref;

  RideActionController(this._ref) : super(const RideActionState());

  BackendApiClient get _api => _ref.read(backendApiClientProvider);
  String? get _uid => _ref.read(authStateProvider).value?.uid;
  String? get _name => _ref.read(currentUserProvider).value?.name;
  String? get _phone => _ref.read(currentUserProvider).value?.phone;
  double? get _lat => _ref.read(currentLocationProvider).value?.latitude;
  double? get _lng => _ref.read(currentLocationProvider).value?.longitude;

  // ── WebSocket Event Handlers ───────────────────────────────────────────────
  // Called by WsEventRouter when backend events arrive.

  void handleRideMatchedEvent(BackendEvent event) {
    final driverUid = event.payload['driver_uid'] as String?;
    final matchId = event.payload['match_id'] as String? ?? event.rideId;
    debugPrint('[RideAction] ride.matched → driver=$driverUid, matchId=$matchId');
    state = state.copyWith(
      matchedDriverUid: driverUid,
      matchId: matchId,
    );
  }

  void handleRideAcceptedEvent(BackendEvent event) {
    debugPrint('[RideAction] ride.accepted → driver confirmed pickup');
    state = state.copyWith(
      status: RideActionStatus.requesting,
      message: 'Driver is on the way!',
      matchedDriverUid: event.payload['driver_uid'] as String? ?? state.matchedDriverUid,
    );
  }

  void handleRideRejectedEvent(BackendEvent event) {
    debugPrint('[RideAction] ride.rejected → looking for next driver');
    state = state.copyWith(
      status: RideActionStatus.requesting,
      message: event.payload['message'] as String? ?? 'Looking for another driver...',
      matchedDriverUid: null,
      matchId: null,
    );
  }

  void handleRideCancelledEvent(BackendEvent event) {
    debugPrint('[RideAction] ride.cancelled → ride cancelled');
    state = const RideActionState(
      status: RideActionStatus.idle,
      message: 'Ride was cancelled.',
    );
  }

  void handleRideCompletedEvent(BackendEvent event) {
    debugPrint('[RideAction] ride.completed → ride complete');
    state = const RideActionState(status: RideActionStatus.idle);
  }

  // ── Incoming Ride Request (Driver side) ───────────────────────────────────
  // This is just stored so the UI can display the details.
  // Driver calls acceptMatch / rejectMatch.

  void handleIncomingRideRequest(BackendEvent event) {
    // Stored in a separate provider — see incomingRideRequestProvider
  }

  // ── Book Ride (Passenger) ─────────────────────────────────────────────────

  Future<void> bookRide() async {
    final uid = _uid;
    final lat = _lat;
    final lng = _lng;

    if (uid == null || lat == null || lng == null) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Location or session unavailable.',
      );
      return;
    }

    state = state.copyWith(status: RideActionStatus.loading);

    try {
      final result = await _api.createRideRequest(
        lat,
        lng,
        pickupAccuracyMeters: _ref.read(currentLocationProvider).value?.accuracy,
      );

      if (result.isExpired) {
        state = state.copyWith(
          status: RideActionStatus.idle,
          message: 'No drivers available nearby. Please try again.',
        );
        return;
      }

      state = state.copyWith(
        status: RideActionStatus.requesting,
        backendRequestId: result.requestId,
        matchedDriverUid: result.driverUid,
        message: result.message,
      );
      debugPrint('[RideAction] Ride requested → id=${result.requestId}');
    } on BackendNetworkException {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Network error. Please check your connection.',
      );
    } on BackendServerException catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Server error: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to book ride: $e',
      );
    }
  }

  Future<void> cancelRide() async {
    final requestId = state.backendRequestId;

    state = state.copyWith(status: RideActionStatus.loading);

    try {
      if (requestId != null) {
        await _api.cancelRideRequest(requestId);
      }
      state = const RideActionState(status: RideActionStatus.idle);
      debugPrint('[RideAction] Ride cancelled');
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to cancel: $e',
      );
    }
  }

  // ── Driver: Accept Match ──────────────────────────────────────────────────

  Future<MatchActionResult?> acceptMatch(String matchId) async {
    state = state.copyWith(status: RideActionStatus.loading);
    try {
      final result = await _api.acceptMatch(matchId);
      state = state.copyWith(
        status: RideActionStatus.idle,
        matchId: matchId,
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to accept: $e',
      );
      return null;
    }
  }

  // ── Driver: Reject Match ──────────────────────────────────────────────────

  Future<MatchActionResult?> rejectMatch(String matchId) async {
    state = state.copyWith(status: RideActionStatus.loading);
    try {
      final result = await _api.rejectMatch(matchId);
      state = const RideActionState(status: RideActionStatus.idle);
      return result;
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to reject: $e',
      );
      return null;
    }
  }

  // ── Complete Ride ─────────────────────────────────────────────────────────

  Future<void> completeRide() async {
    final rideId = state.backendRequestId ?? state.matchId;
    if (rideId == null) return;
    try {
      await _api.completeRide(rideId);
      state = const RideActionState(status: RideActionStatus.idle);
    } catch (e) {
      debugPrint('[RideAction] Complete ride failed: $e');
    }
  }

  // ── SOS ───────────────────────────────────────────────────────────────────

  Future<SosResult?> triggerSos() async {
    final rideId = state.backendRequestId ?? state.matchId ?? 'no-ride';
    final lat = _lat;
    final lng = _lng;
    try {
      return await _api.triggerSos(rideId, latitude: lat, longitude: lng);
    } catch (e) {
      debugPrint('[RideAction] SOS failed: $e');
      return null;
    }
  }

  // ── Ride Share (RTDB — temporary, migrated to backend later) ─────────────

  Future<void> enableRideShare({
    double? destLatitude,
    double? destLongitude,
    int seatsAvailable = 1,
  }) async {
    final rtdb = _ref.read(rtdbServiceProvider);
    final uid = _uid;
    final lat = _lat;
    final lng = _lng;

    if (rtdb == null || uid == null || lat == null || lng == null) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Location or service unavailable.',
      );
      return;
    }

    state = state.copyWith(status: RideActionStatus.loading);

    try {
      final share = RideShareModel(
        uid: uid,
        name: _name ?? 'Passenger',
        phone: _phone ?? '',
        latitude: lat,
        longitude: lng,
        destLatitude: destLatitude,
        destLongitude: destLongitude,
        seatsAvailable: seatsAvailable,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await rtdb.pushRideShare(share);
      state = state.copyWith(status: RideActionStatus.sharing);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to enable ride-share: $e',
      );
    }
  }

  Future<void> disableRideShare() async {
    final rtdb = _ref.read(rtdbServiceProvider);
    final uid = _uid;
    if (rtdb == null || uid == null) return;

    state = state.copyWith(status: RideActionStatus.loading);
    try {
      await rtdb.removeRideShare(uid);
      state = state.copyWith(status: RideActionStatus.idle);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to disable ride-share: $e',
      );
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final rideActionControllerProvider =
    StateNotifierProvider<RideActionController, RideActionState>((ref) {
  return RideActionController(ref);
});

// ── Incoming Ride Request (Driver side) ───────────────────────────────────────

/// Holds the most recent incoming ride.requested event payload for the driver UI.
/// Cleared when the driver accepts or rejects.
final incomingRideRequestProvider =
    StateProvider<BackendEvent?>((ref) => null);
