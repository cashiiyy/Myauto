import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../models/backend_event.dart';
import '../models/nearby_driver_model.dart';
import '../providers/auth_provider.dart';
import '../providers/backend_client_provider.dart';
import '../providers/location_provider.dart';
import '../providers/ws_provider.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class BackendDriversState {
  final List<NearbyDriverModel> drivers;
  final bool isLoading;
  final String? error;
  final DateTime? lastUpdated;

  const BackendDriversState({
    this.drivers = const [],
    this.isLoading = false,
    this.error,
    this.lastUpdated,
  });

  BackendDriversState copyWith({
    List<NearbyDriverModel>? drivers,
    bool? isLoading,
    String? error,
    DateTime? lastUpdated,
  }) =>
      BackendDriversState(
        drivers: drivers ?? this.drivers,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Backend-sourced nearby driver state.
///
/// Sources of truth (in order of priority):
/// 1. WebSocket [BackendEventType.driverPresence] events — real-time updates
/// 2. REST polling GET /api/drivers/nearby — every [AppConfig.nearbyDriverPollIntervalSeconds]
///
/// Stale / offline drivers are removed automatically.
class BackendDriversNotifier extends StateNotifier<BackendDriversState> {
  final Ref _ref;
  Timer? _pollTimer;
  ProviderSubscription<AsyncValue<BackendEvent>>? _eventSub;

  BackendDriversNotifier(this._ref) : super(const BackendDriversState()) {
    _subscribeToEvents();
    _startPolling();
  }

  // ── Event subscription ────────────────────────────────────────────────────

  void _subscribeToEvents() {
    _eventSub = _ref.listen<AsyncValue<BackendEvent>>(
      backendEventsProvider,
      (_, next) {
        next.whenData((event) {
          if (event.type == BackendEventType.driverPresence) {
            _handleDriverPresenceEvent(event);
          }
        });
      },
    );
  }

  void _handleDriverPresenceEvent(BackendEvent event) {
    final driverUid = event.payload['driver_uid'] as String?;
    if (driverUid == null) return;

    final driverState = event.payload['state'] as String? ?? 'AVAILABLE';
    final freshness = event.payload['freshness'] as String? ?? 'LIVE';

    // Remove stale/offline drivers
    if (driverState == 'STALE' || driverState == 'OFFLINE' || freshness == 'OFFLINE') {
      state = state.copyWith(
        drivers: state.drivers.where((d) => d.driverUid != driverUid).toList(),
        lastUpdated: DateTime.now(),
      );
      debugPrint('[BackendDrivers] Removed stale/offline driver: $driverUid');
      return;
    }

    // Update existing driver or add new one
    final existingIndex = state.drivers.indexWhere((d) => d.driverUid == driverUid);
    if (existingIndex >= 0) {
      final updated = List<NearbyDriverModel>.from(state.drivers);
      updated[existingIndex] =
          updated[existingIndex].copyWithPresenceEvent(event.payload);
      state = state.copyWith(drivers: updated, lastUpdated: DateTime.now());
    } else {
      // New driver appeared — build from event payload
      final newDriver = NearbyDriverModel(
        driverUid: driverUid,
        latitude: (event.payload['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (event.payload['longitude'] as num?)?.toDouble() ?? 0,
        distanceKm: (event.payload['distance_km'] as num?)?.toDouble() ?? 0,
        headingDegrees: (event.payload['heading_degrees'] as num?)?.toDouble(),
        accuracyMeters: (event.payload['accuracy_meters'] as num?)?.toDouble(),
        freshness: freshness,
        isAvailable: driverState == 'AVAILABLE',
      );
      state = state.copyWith(
        drivers: [...state.drivers, newDriver],
        lastUpdated: DateTime.now(),
      );
    }
  }

  // ── REST polling ──────────────────────────────────────────────────────────

  void _startPolling() {
    _poll(); // Immediate first fetch
    _pollTimer = Timer.periodic(
      const Duration(seconds: AppConfig.nearbyDriverPollIntervalSeconds),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    final position = _ref.read(currentLocationProvider).valueOrNull;
    if (position == null) {
      debugPrint('[MAP DIAG] _poll skipped: currentLocationProvider is null');
      return;
    }

    final uid = _ref.read(authStateProvider).valueOrNull?.uid;
    final apiClient = _ref.read(backendApiClientProvider);

    try {
      final drivers = await apiClient.getNearbyDrivers(
        position.latitude,
        position.longitude,
        radiusKm: AppConfig.nearbyDriverRadiusKm,
      );

      // Exclude self (driver viewing their own position)
      final filtered =
          uid != null ? drivers.where((d) => d.driverUid != uid).toList() : drivers;

      debugPrint(
        '🛺 [MAP DIAG] nearby_drivers_http_status=200 nearby_drivers_count=${filtered.length} '
        'my_lat=${position.latitude.toStringAsFixed(5)} my_lng=${position.longitude.toStringAsFixed(5)}',
      );
      for (final d in filtered) {
        debugPrint(
          '   ↳ [MAP DIAG] driver_uid=${d.driverUid} lat=${d.latitude} lng=${d.longitude} '
          'dist_km=${d.distanceKm.toStringAsFixed(2)} freshness=${d.freshness} is_available=${d.isAvailable}',
        );
      }

      state = state.copyWith(
        drivers: filtered,
        isLoading: false,
        error: null,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      debugPrint('🔴 [MAP DIAG] nearby_drivers_poll_failed: $e');
      // Keep stale data visible — just note the error
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Force an immediate refresh (e.g., on map reload button).
  Future<void> refresh() => _poll();

  @override
  void dispose() {
    _pollTimer?.cancel();
    _eventSub?.close();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final backendDriversProvider =
    StateNotifierProvider<BackendDriversNotifier, BackendDriversState>((ref) {
  return BackendDriversNotifier(ref);
});
