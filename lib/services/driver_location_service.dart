import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../models/user_model.dart';
import '../services/backend/api_client.dart';

/// Manages the GPS → Backend push loop for a logged-in driver.
///
/// Uses [Geolocator.getPositionStream] rather than a fixed timer so updates
/// are triggered by meaningful movement (5m) rather than wall-clock time.
///
/// Backend is the primary destination. RTDB writes are removed.
/// Raw GPS coordinates are sent to the backend WITHOUT modification —
/// smoothing is only for visual marker presentation in the UI.
///
/// Lifecycle is owned by [HomeScreen]:
///   call start() in initState (via postFrameCallback)
///   call stop() + dispose() when going offline or in dispose()
class DriverLocationService with WidgetsBindingObserver {
  final BackendApiClient _api;
  final UserModel _driver;

  StreamSubscription<Position>? _positionSub;
  bool _running = false;
  int _sequence = 0;

  static const _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5, // metres — send on meaningful movement
  );

  DriverLocationService(this._api, this._driver);

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _startStream();
    debugPrint('[DriverService] Started for ${_driver.uid}');
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _positionSub?.cancel();
    _positionSub = null;
    debugPrint('[DriverService] Stopped for ${_driver.uid}');
  }

  void dispose() {
    _positionSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  // ── Lifecycle: pause stream when backgrounded ─────────────────────────────
  //
  // NOTE: Background GPS is NOT tested on physical hardware in this phase.
  // The stream is paused/resumed on lifecycle events to save battery.
  // Background tracking can be added via a foreground service in a future phase.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startStream();
        debugPrint('[DriverService] Resumed — GPS stream restarted');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _positionSub?.cancel();
        _positionSub = null;
        debugPrint('[DriverService] Paused — GPS stream stopped');
        break;
    }
  }

  // ── Stream management ─────────────────────────────────────────────────────

  void _startStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(_onPosition, onError: _onError);
  }

  Future<void> _onPosition(Position pos) async {
    debugPrint(
      '🟢 [DriverService] GPS: ${pos.latitude}, ${pos.longitude} '
      'acc=${pos.accuracy.toStringAsFixed(1)}m '
      'speed=${pos.speed.toStringAsFixed(1)}m/s',
    );

    // IMPORTANT: send RAW coordinates — never modify before sending.
    // Visual smoothing is done only in the map marker layer.
    final payload = LocationPayload(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy,
      altitude: pos.altitude,
      speedMps: pos.speed,
      headingDegrees: _normaliseHeading(pos.heading),
      capturedAt: pos.timestamp.millisecondsSinceEpoch,
      sequence: ++_sequence,
      role: 'driver',
    );

    try {
      await _api.updateLocation(payload);
      debugPrint('🟢 [DriverService] Location sent to backend ✅');
    } catch (e) {
      debugPrint('🔴 [DriverService] Location send failed: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('🔴 [DriverService] GPS stream error: $error');
  }

  /// Normalize heading to 0–359.9 degrees.
  /// Geolocator returns -1 if heading is unavailable; the backend rejects
  /// values outside [0, 360).
  double? _normaliseHeading(double heading) {
    if (heading < 0) return null;
    return heading % 360.0;
  }
}
