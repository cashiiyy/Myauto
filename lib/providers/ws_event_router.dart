import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/backend_event.dart';
import '../providers/auth_provider.dart';
import '../providers/backend_client_provider.dart';
import '../providers/ride_action_provider.dart';
import '../providers/ws_provider.dart';

/// Routes incoming WebSocket events to the appropriate Riverpod controllers.
///
/// This notifier lives for the app lifetime (it is watched from the root of
/// the widget tree via [WsEventRouterInit]) and ensures that every backend
/// event reaches its handler exactly once — after deduplication by the
/// WebSocket client itself.
///
/// Routing table
/// -------------
///   ride.requested   → incomingRideRequestProvider (driver sees passenger)
///   ride.matched     → rideActionController (passenger confirmed driver found)
///   ride.accepted    → rideActionController (passenger: driver is coming)
///   ride.rejected    → rideActionController (passenger: finding next driver)
///   ride.cancelled   → rideActionController (both parties)
///   ride.completed   → rideActionController (both parties)
///   error            → debug log
///   everything else  → debug log
class WsEventRouter extends Notifier<void> {
  @override
  void build() {
    // Subscribe to all backend events and dispatch them
    ref.listen<AsyncValue<BackendEvent>>(
      backendEventsProvider,
      (_, next) {
        next.whenData(_dispatch);
      },
    );

    // Durability: When WS connects, query server for any pending ride assigned to driver
    ref.listen<AsyncValue<WsConnectionState>>(
      wsConnectionStateProvider,
      (prev, next) {
        if (next.valueOrNull == WsConnectionState.connected) {
          _checkPendingDriverRide();
        }
      },
    );
  }

  Future<void> _checkPendingDriverRide() async {
    final user = ref.read(currentUserProvider).value;
    if (user != null && user.role.toLowerCase() == 'driver') {
      try {
        final api = ref.read(backendApiClientProvider);
        final pendingEvent = await api.getDriverPendingRide();
        if (pendingEvent != null) {
          final currentRequest = ref.read(incomingRideRequestProvider);
          if (currentRequest?.rideId == pendingEvent.rideId) {
            _log('🔄 [DIAG] Pending ride already active: ${pendingEvent.rideId}. Ignoring duplicate.');
          } else {
            _log('🔄 [DIAG] Recovered pending ride on reconnect: ${pendingEvent.rideId}');
            ref.read(incomingRideRequestProvider.notifier).state = pendingEvent;
          }
        }
      } catch (e) {
        _log('[DIAG] Failed to query pending ride for driver: $e');
      }
    }
  }

  void _dispatch(BackendEvent event) {
    _log('[DIAG] Routing event: ${event.type.value}, rideId: ${event.rideId}');
    final rideCtrl = ref.read(rideActionControllerProvider.notifier);

    switch (event.type) {
      case BackendEventType.rideRequested:
        // Driver receives this — store it for the accept/reject sheet
        final currentRequest = ref.read(incomingRideRequestProvider);
        if (currentRequest?.rideId == event.rideId) {
          _log('[DIAG] Duplicate ride.requested ignored for ride=${event.rideId}');
        } else {
          _log('[DIAG] Driver received ride.requested! Updating incomingRideRequestProvider for ride=${event.rideId}');
          ref.read(incomingRideRequestProvider.notifier).state = event;
        }

      case BackendEventType.rideMatched:
        // Passenger receives this — a driver has been found
        rideCtrl.handleRideMatchedEvent(event);

      case BackendEventType.rideAccepted:
        // Passenger receives this — driver accepted
        rideCtrl.handleRideAcceptedEvent(event);

      case BackendEventType.rideRejected:
        // Passenger receives this — driver rejected, searching for next
        rideCtrl.handleRideRejectedEvent(event);

      case BackendEventType.rideCancelled:
        rideCtrl.handleRideCancelledEvent(event);

      case BackendEventType.rideCompleted:
        rideCtrl.handleRideCompletedEvent(event);

      case BackendEventType.sosTriggered:
        // Backend confirmed SOS — log only (phone call already made)
        _log('🚨 SOS event acknowledged by server: ride=${event.rideId}');

      case BackendEventType.error:
        _log('⚠️  Backend error event: ${event.payload['message']}');

      case BackendEventType.driverPresence:
      case BackendEventType.driverAvailability:
      case BackendEventType.locationUpdate:
        // These are consumed by backendDriversProvider directly
        break;

      case BackendEventType.heartbeat:
      case BackendEventType.unknown:
        break;
    }
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[WsEventRouter] $msg');
  }
}

final wsEventRouterProvider = NotifierProvider<WsEventRouter, void>(() {
  return WsEventRouter();
});
