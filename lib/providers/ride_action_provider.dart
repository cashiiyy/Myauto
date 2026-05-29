import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ride_request_model.dart';
import '../models/ride_share_model.dart';
import '../services/rtdb_service.dart';
import 'auth_provider.dart';
import 'rtdb_provider.dart';
import 'location_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum RideActionStatus { idle, requesting, sharing, loading, error }

class RideActionState {
  final RideActionStatus status;
  final String? message;

  const RideActionState({
    this.status = RideActionStatus.idle,
    this.message,
  });

  bool get isRequesting => status == RideActionStatus.requesting;
  bool get isSharing => status == RideActionStatus.sharing;

  RideActionState copyWith({
    RideActionStatus? status,
    String? message,
  }) =>
      RideActionState(
        status: status ?? this.status,
        message: message ?? this.message,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

/// Handles all passenger-side booking and ride-sharing actions against RTDB.
///
/// Usage in UI:
/// ```dart
/// final controller = ref.read(rideActionControllerProvider.notifier);
/// await controller.bookRide();       // when "Book Ride" button tapped
/// await controller.cancelRide();     // when request cancelled
/// await controller.enableRideShare(destLat, destLng);  // toggle ON
/// await controller.disableRideShare();                 // toggle OFF
/// ```
class RideActionController extends StateNotifier<RideActionState> {
  final RtdbService? _rtdb;
  final String? _uid;
  final String? _name;
  final String? _phone;
  final Position? _currentPosition;

  RideActionController({
    required RtdbService? rtdb,
    required String? uid,
    required String? name,
    required String? phone,
    required Position? currentPosition,
  })  : _rtdb = rtdb,
        _uid = uid,
        _name = name,
        _phone = phone,
        _currentPosition = currentPosition,
        super(const RideActionState());

  // ── Book Ride ────────────────────────────────────────────────────

  /// Push the passenger's current location into `ride_requests/{uid}`.
  /// Call this when the user taps "Book Ride".
  Future<void> bookRide() async {
    if (_rtdb == null || _uid == null || _currentPosition == null) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Location or service unavailable.',
      );
      return;
    }

    state = state.copyWith(status: RideActionStatus.loading);

    try {
      final request = RideRequestModel(
        uid: _uid,
        name: _name ?? 'Passenger',
        phone: _phone ?? '',
        latitude: _currentPosition.latitude,
        longitude: _currentPosition.longitude,
        status: 'waiting',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _rtdb.pushRideRequest(request);
      state = state.copyWith(status: RideActionStatus.requesting);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to book ride: $e',
      );
    }
  }

  /// Remove the passenger's entry from `ride_requests/{uid}`.
  /// Call this when the user cancels their request.
  Future<void> cancelRide() async {
    if (_rtdb == null || _uid == null) return;
    state = state.copyWith(status: RideActionStatus.loading);
    try {
      await _rtdb.removeRideRequest(_uid);
      state = state.copyWith(status: RideActionStatus.idle);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to cancel: $e',
      );
    }
  }

  // ── Ride Share ───────────────────────────────────────────────────

  /// Push the passenger's location + destination into `ride_shares/{uid}`.
  /// Call this when the user toggles "Enable Ride-Share" ON.
  Future<void> enableRideShare({
    double? destLatitude,
    double? destLongitude,
    int seatsAvailable = 1,
  }) async {
    if (_rtdb == null || _uid == null || _currentPosition == null) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Location or service unavailable.',
      );
      return;
    }

    state = state.copyWith(status: RideActionStatus.loading);

    try {
      final share = RideShareModel(
        uid: _uid,
        name: _name ?? 'Passenger',
        phone: _phone ?? '',
        latitude: _currentPosition.latitude,
        longitude: _currentPosition.longitude,
        destLatitude: destLatitude,
        destLongitude: destLongitude,
        seatsAvailable: seatsAvailable,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _rtdb.pushRideShare(share);
      state = state.copyWith(status: RideActionStatus.sharing);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to enable ride-share: $e',
      );
    }
  }

  /// Remove the passenger's entry from `ride_shares/{uid}`.
  /// Call this when the user toggles "Enable Ride-Share" OFF.
  Future<void> disableRideShare() async {
    if (_rtdb == null || _uid == null) return;
    state = state.copyWith(status: RideActionStatus.loading);
    try {
      await _rtdb.removeRideShare(_uid);
      state = state.copyWith(status: RideActionStatus.idle);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to disable ride-share: $e',
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final rideActionControllerProvider =
    StateNotifierProvider<RideActionController, RideActionState>((ref) {
  final rtdb = ref.watch(rtdbServiceProvider);
  final authUser = ref.watch(authStateProvider).value;
  final userModel = ref.watch(currentUserProvider).value;
  final position = ref.watch(currentLocationProvider).value;

  return RideActionController(
    rtdb: rtdb,
    uid: authUser?.uid,
    name: userModel?.name,
    phone: userModel?.phone,
    currentPosition: position,
  );
});
