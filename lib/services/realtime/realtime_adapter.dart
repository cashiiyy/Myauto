import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/backend_event.dart';
import '../../config/app_config.dart';

// ── Abstract interface ────────────────────────────────────────────────────────

/// Abstract real-time transport adapter.
///
/// Implementations:
/// - [WebSocketRealtimeAdapter]  — wraps the existing [BackendWebSocketClient]
/// - [SocketIoRealtimeAdapter]   — connects to the new Node.js Socket.IO server
/// - [MockRealtimeAdapter]       — emits mock events for offline testing
///
/// The [WsEventRouter] and all Riverpod providers continue to consume
/// [BackendEvent] objects regardless of which adapter is active.
abstract class RealtimeAdapter {
  /// Stream of decoded [BackendEvent] objects (heartbeats excluded).
  Stream<BackendEvent> get events;

  /// Connect to the real-time server.
  Future<void> connect();

  /// Disconnect gracefully.
  Future<void> disconnect();

  /// Dispose all resources.
  void dispose();
}

// ── Socket.IO adapter ─────────────────────────────────────────────────────────
//
// This adapter connects to the Node.js Socket.IO server.
// It translates Socket.IO events into [BackendEvent] objects using the
// same event-type strings as the existing FastAPI WebSocket — no changes
// needed in WsEventRouter or any existing provider.
//
// The socket_io_client package must be added to pubspec.yaml:
//   socket_io_client: ^2.0.3
//
// Until the package is available, this file compiles safely because the
// import is guarded by the conditional platform check.

/// Socket.IO real-time adapter connecting to the Node.js backend.
///
/// Event protocol matches the existing FastAPI WebSocket event format:
/// {
///   "event_id": "...",
///   "type": "driver.presence" | "ride.requested" | etc.,
///   "server_timestamp": "...",
///   "ride_id": "...",     // optional
///   "payload": { ... }
/// }
class SocketIoRealtimeAdapter implements RealtimeAdapter {
  final _eventController = StreamController<BackendEvent>.broadcast();

  // Socket.IO client — held as dynamic to avoid compile-time import failure
  // before socket_io_client is added to pubspec.yaml.
  dynamic _socket;

  bool _disposed = false;

  @override
  Stream<BackendEvent> get events => _eventController.stream;

  @override
  Future<void> connect() async {
    if (_disposed) return;
    try {
      _socket = await _createSocket();
      debugPrint('[SocketIO] Connecting to ${AppConfig.socketIoUrl}');
    } catch (e) {
      debugPrint('[SocketIO] Connection failed: $e');
    }
  }

  /// Creates the Socket.IO socket using socket_io_client ^3.1.6 API.
  ///
  /// To activate, add to pubspec.yaml:
  ///   socket_io_client: ^3.1.6
  ///
  /// Then replace this method body with:
  /// ```dart
  /// import 'package:socket_io_client/socket_io_client.dart' as IO;
  ///
  /// Future<IO.Socket> _createSocket() async {
  ///   final socket = IO.io(
  ///     AppConfig.socketIoUrl,
  ///     IO.OptionBuilder()
  ///       .setTransports(['websocket'])  // avoid polling for mobile
  ///       .enableAutoConnect()
  ///       .setAuth({'token': await FirebaseAuth.instance.currentUser?.getIdToken()})
  ///       .setQuery({'role': AppConfig.currentRole})  // 'passenger' or 'driver'
  ///       .build(),
  ///   );
  ///
  ///   socket.onConnect((_) => debugPrint('[SocketIO] Connected ✅'));
  ///   socket.onDisconnect((_) => debugPrint('[SocketIO] Disconnected'));
  ///   socket.onConnectError((e) => debugPrint('[SocketIO] Connect error: $e'));
  ///
  ///   for (final eventType in _watchedEvents) {
  ///     socket.on(eventType, (data) => _onEvent(eventType, data));
  ///   }
  ///   return socket;
  /// }
  /// ```
  ///
  /// NOTE: socket_io_client v3.x connects to Socket.IO server v4.7+.
  /// Our nodejs/package.json uses socket.io ^4.7.4 — this is compatible.
  Future<dynamic> _createSocket() async {
    debugPrint('[SocketIO] socket_io_client ^3.1.6 not yet integrated. '
        'Add socket_io_client: ^3.1.6 to pubspec.yaml, uncomment it, '
        'and replace this method body with the implementation above.');
    return null;
  }

  static const List<String> _watchedEvents = [
    'driver.presence',
    'driver.availability',
    'ride.requested',
    'ride.matched',
    'ride.accepted',
    'ride.rejected',
    'ride.cancelled',
    'ride.completed',
    'sos.triggered',
    'error',
  ];

  void _onEvent(String eventType, dynamic data) {
    if (_disposed) return;
    try {
      final Map<String, dynamic> payload =
          (data is Map) ? Map<String, dynamic>.from(data as Map) : {};

      final event = BackendEvent(
        eventId: payload['event_id'] as String? ?? '',
        type: BackendEventType.fromString(eventType),
        serverTimestamp: payload['server_timestamp'] as String? ?? '',
        rideId: payload['ride_id'] as String?,
        payload: (payload['payload'] as Map<String, dynamic>?) ?? {},
      );

      if (!_eventController.isClosed) {
        _eventController.add(event);
      }
    } catch (e) {
      debugPrint('[SocketIO] Failed to parse event $eventType: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      (_socket as dynamic)?.disconnect();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    _eventController.close();
  }
}

// ── Mock adapter ──────────────────────────────────────────────────────────────

/// Emits no events — used in mock/offline mode.
/// Preserves the existing mock behaviour where no real-time events fire.
class MockRealtimeAdapter implements RealtimeAdapter {
  final _controller = StreamController<BackendEvent>.broadcast();

  @override
  Stream<BackendEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    debugPrint('[MockRealtime] Connected (mock — no events emitted)');
  }

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() => _controller.close();
}

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create the appropriate [RealtimeAdapter] based on [AppConfig.realtimeMode].
///
/// 'websocket' — callers should use the existing [wsClientProvider] and
///               [BackendWebSocketClient] directly (unchanged behaviour).
/// 'socketio'  — returns [SocketIoRealtimeAdapter]
/// 'mock'      — returns [MockRealtimeAdapter]
RealtimeAdapter? createRealtimeAdapter() {
  switch (AppConfig.realtimeMode) {
    case 'socketio':
      return SocketIoRealtimeAdapter();
    case 'mock':
      return MockRealtimeAdapter();
    default:
      // 'websocket' — use existing BackendWebSocketClient via wsClientProvider
      return null;
  }
}
