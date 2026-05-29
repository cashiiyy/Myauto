import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../models/driver_location_model.dart';
import '../models/user_model.dart';
import 'rtdb_service.dart';

/// Manages the periodic GPS → RTDB push loop for a logged-in driver.
///
/// Lifecycle is owned by [HomeScreen] — call [start()] in initState,
/// [dispose()] in dispose(). This is a plain class (not StateNotifier) so
/// the widget controls the lifetime directly with no Riverpod disposal race.
class DriverLocationService with WidgetsBindingObserver {
  final RtdbService _rtdb;
  final UserModel _driver;

  Timer? _timer;
  bool _running = false;
  static const _interval = Duration(seconds: 5);

  DriverLocationService(this._rtdb, this._driver);

  // ── Public API ────────────────────────────────────────────────────

  /// Call once from HomeScreen.initState (via postFrameCallback).
  Future<void> start() async {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    // Register onDisconnect BEFORE first push — Firebase handles cleanup on drop
    await _rtdb.registerDriverOnDisconnect(_driver.uid);
    await _pushLocation(); // immediate first push
    _startTimer();
    debugPrint('[DriverService] Started for ${_driver.uid}');
  }

  /// Call from HomeScreen.dispose or when driver goes offline.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _stopTimer();
    await _rtdb.removeDriver(_driver.uid);
    debugPrint('[DriverService] Stopped for ${_driver.uid}');
  }

  void dispose() {
    _stopTimer();
    WidgetsBinding.instance.removeObserver(this);
  }

  // ── Lifecycle: pause timer in background ──────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startTimer();
        debugPrint('[DriverService] Resumed');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _stopTimer();
        debugPrint('[DriverService] Paused');
        break;
    }
  }

  // ── Internals ─────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _pushLocation());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _pushLocation() async {
    debugPrint('🟡 [STAGE-A] _pushLocation() called for ${_driver.uid}');
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      debugPrint('🟢 [STAGE-A] GPS OK: ${pos.latitude}, ${pos.longitude}');
      await _rtdb.updateDriverLocation(DriverLocationModel(
        uid: _driver.uid,
        name: _driver.name,
        phone: _driver.phone,
        vehicleNumber: _driver.autoRegistrationNumber ?? '',
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading,
        isAvailable: _driver.isAvailable ?? true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      debugPrint('🟢 [STAGE-A] RTDB push SUCCESS for ${_driver.uid}');
    } catch (e, st) {
      debugPrint('🔴 [STAGE-A] Push FAILED: $e');
      debugPrint('🔴 [STAGE-A] Stack: $st');
    }
  }
}
