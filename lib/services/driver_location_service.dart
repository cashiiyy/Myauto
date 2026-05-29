import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/driver_location_model.dart';
import '../models/user_model.dart';
import 'rtdb_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum DriverServiceStatus { idle, running, paused, error }

class DriverServiceState {
  final DriverServiceStatus status;
  final String? errorMessage;

  const DriverServiceState({
    this.status = DriverServiceStatus.idle,
    this.errorMessage,
  });

  DriverServiceState copyWith({
    DriverServiceStatus? status,
    String? errorMessage,
  }) =>
      DriverServiceState(
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

/// Manages the periodic GPS → RTDB push loop for a logged-in driver.
///
/// Key behaviours:
/// - Pushes location every 5 seconds while [start()] is active.
/// - Registers `onDisconnect().remove()` so the RTDB entry is cleaned up
///   automatically if the TCP connection to Firebase drops (app kill / crash).
/// - Pauses when the host app goes to background and resumes on foreground.
/// - Disposes the timer cleanly when the Riverpod provider is destroyed.
class DriverLocationService extends StateNotifier<DriverServiceState>
    with WidgetsBindingObserver {
  final RtdbService _rtdb;
  final UserModel _driver;

  Timer? _timer;
  static const _interval = Duration(seconds: 5);

  DriverLocationService(this._rtdb, this._driver)
      : super(const DriverServiceState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  // ── Public API ───────────────────────────────────────────────────

  /// Begin pushing GPS data. Call once from [home_screen.dart] initState.
  Future<void> start() async {
    if (state.status == DriverServiceStatus.running) return;

    // Register onDisconnect BEFORE the first push so it's always set.
    await _rtdb.registerDriverOnDisconnect(_driver.uid);

    state = state.copyWith(status: DriverServiceStatus.running);
    await _pushCurrentLocation(); // immediate first push
    _startTimer();
  }

  /// Manually go offline (e.g. driver toggles availability off / logs out).
  Future<void> stop() async {
    _stopTimer();
    await _rtdb.removeDriver(_driver.uid);
    state = state.copyWith(status: DriverServiceStatus.idle);
  }

  // ── WidgetsBindingObserver ───────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final serviceState = this.state; // capture before switch to avoid ambiguity
    switch (state) {
      case AppLifecycleState.resumed:
        if (serviceState.status == DriverServiceStatus.paused) {
          this.state = serviceState.copyWith(status: DriverServiceStatus.running);
          _startTimer();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (serviceState.status == DriverServiceStatus.running) {
          _stopTimer();
          this.state = serviceState.copyWith(status: DriverServiceStatus.paused);
        }
        break;
    }
  }

  // ── Internals ────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _pushCurrentLocation());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _pushCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final model = DriverLocationModel(
        uid: _driver.uid,
        name: _driver.name,
        phone: _driver.phone,
        vehicleNumber: _driver.autoRegistrationNumber ?? '',
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        isAvailable: _driver.isAvailable ?? true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await _rtdb.updateDriverLocation(model);
    } catch (e) {
      // Non-fatal: network hiccup or location unavailable — we'll retry on next tick
      debugPrint('[DriverLocationService] Push failed: $e');
    }
  }

  @override
  void dispose() {
    _stopTimer();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
