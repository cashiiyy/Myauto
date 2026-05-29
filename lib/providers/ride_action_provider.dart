import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class RideActionController extends StateNotifier<RideActionState> {
  final Ref _ref;

  RideActionController(this._ref) : super(const RideActionState());

  RtdbService? get _rtdb => _ref.read(rtdbServiceProvider);
  String? get _uid => _ref.read(authStateProvider).value?.uid;
  String? get _name => _ref.read(currentUserProvider).value?.name;
  String? get _phone => _ref.read(currentUserProvider).value?.phone;
  double? get _lat => _ref.read(currentLocationProvider).value?.latitude;
  double? get _lng => _ref.read(currentLocationProvider).value?.longitude;

  // ── Book Ride ────────────────────────────────────────────────────

  Future<void> bookRide() async {
    final rtdb = _rtdb;
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
      final request = RideRequestModel(
        uid: uid,
        name: _name ?? 'Passenger',
        phone: _phone ?? '',
        latitude: lat,
        longitude: lng,
        status: 'waiting',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await rtdb.pushRideRequest(request);
      state = state.copyWith(status: RideActionStatus.requesting);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to book ride: $e',
      );
    }
  }

  Future<void> cancelRide() async {
    final rtdb = _rtdb;
    final uid = _uid;
    if (rtdb == null || uid == null) return;
    
    state = state.copyWith(status: RideActionStatus.loading);
    try {
      await rtdb.removeRideRequest(uid);
      state = state.copyWith(status: RideActionStatus.idle);
    } catch (e) {
      state = state.copyWith(
        status: RideActionStatus.error,
        message: 'Failed to cancel: $e',
      );
    }
  }

  // ── Ride Share ───────────────────────────────────────────────────

  Future<void> enableRideShare({
    double? destLatitude,
    double? destLongitude,
    int seatsAvailable = 1,
  }) async {
    final rtdb = _rtdb;
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
    final rtdb = _rtdb;
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

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final rideActionControllerProvider =
    StateNotifierProvider<RideActionController, RideActionState>((ref) {
  return RideActionController(ref);
});
