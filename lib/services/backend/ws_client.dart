import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../../config/app_config.dart';
import '../../models/backend_event.dart';

// ── Connection state ──────────────────────────────────────────────────────────

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  authFailed,
  error,
}

// ── WebSocket Client ──────────────────────────────────────────────────────────

/// Manages one persistent, authenticated WebSocket connection to the backend.
///
/// Features:
/// - Firebase ID token in query param (`?token=...`)
/// - Server heartbeat ping/pong every [AppConfig.wsHeartbeatIntervalSeconds]s
/// - Exponential backoff reconnect (1 → 2 → 4 → 8 … max 60s)
/// - Token refresh before reconnect
/// - Event deduplication via a fixed-size LRU set
/// - All incoming events exposed as [events] stream
///
/// Lifecycle:
///   final ws = BackendWebSocketClient();
///   await ws.connect();
///   ws.events.listen((event) { ... });
///   await ws.disconnect();
class BackendWebSocketClient extends ChangeNotifier {
  final FirebaseAuth? _auth;

  BackendWebSocketClient({FirebaseAuth? auth})
      : _auth = auth;

  // ── State ─────────────────────────────────────────────────────────────────
  WsConnectionState _connectionState = WsConnectionState.disconnected;
  WsConnectionState get connectionState => _connectionState;

  // ── Streams ───────────────────────────────────────────────────────────────
  final _eventController = StreamController<BackendEvent>.broadcast();
  Stream<BackendEvent> get events => _eventController.stream;

  // ── Internal ──────────────────────────────────────────────────────────────
  IOWebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  bool _disposed = false;
  bool _intentionalDisconnect = false;
  int _reconnectAttempts = 0;

  // Diagnostic state
  DateTime? _connectedAt;
  DateTime? _lastMessageAt;
  String? _lastError;
  int get reconnectCount => _reconnectAttempts;
  DateTime? get connectedAt => _connectedAt;
  DateTime? get lastMessageAt => _lastMessageAt;
  String? get lastError => _lastError;

  // Event deduplication — keeps the last N event IDs
  final Set<String> _seenEventIds = {};
  static const int _dedupeSize = AppConfig.wsDeduplicationCacheSize;

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_disposed) return;
    if (_connectionState == WsConnectionState.connected ||
        _connectionState == WsConnectionState.connecting) {
      return;
    }
    _intentionalDisconnect = false;
    await _doConnect();
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _cancelTimers();
    await _channelSub?.cancel();
    _channelSub = null;
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _setConnectionState(WsConnectionState.disconnected);
  }

  /// Send a ping to the server to keep the connection alive.
  void sendPing() {
    _send({'type': 'ping'});
  }

  /// Send a pong in response to a server heartbeat.
  void sendPong() {
    _send({'type': 'pong'});
  }

  /// Subscribe to events for a specific ride session.
  void subscribeRide(String rideId) {
    _send({'type': 'subscribe_ride', 'payload': {'ride_id': rideId}});
  }

  void unsubscribeRide(String rideId) {
    _send({'type': 'unsubscribe_ride', 'payload': {'ride_id': rideId}});
  }

  // ── Connection logic ──────────────────────────────────────────────────────

  Future<void> _doConnect() async {
    if (_disposed) return;
    _setConnectionState(WsConnectionState.connecting);

    // 1. Get a fresh Firebase ID token
    String? token;
    try {
      token = await _auth?.currentUser?.getIdToken();
      if (token == null && !AppConfig.mockMode) {
        debugPrint('[WsClient] No authenticated user — cannot connect');
        _setConnectionState(WsConnectionState.authFailed);
        return;
      }
    } catch (e) {
      debugPrint('[WsClient] Token fetch failed: $e');
      _setConnectionState(WsConnectionState.authFailed);
      return;
    }

    // 2. Build WSS URL with token query param
    final wsUrl = AppConfig.mockMode
        ? 'ws://localhost:9999/ws?token=mock'
        : '${AppConfig.backendWsUrl}?token=${token ?? "mock"}';

    debugPrint('[WsClient] Connecting to $wsUrl (attempt ${_reconnectAttempts + 1})');

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );

      // 3. Wait for the connection to be established
      await _channel!.ready.timeout(const Duration(seconds: 10));

      _reconnectAttempts = 0;
      _connectedAt = DateTime.now();
      _lastError = null;
      _setConnectionState(WsConnectionState.connected);
      debugPrint('[WsClient] Connected ✅');

      // 4. Start listening to incoming events
      _channelSub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // 5. Start heartbeat
      _startHeartbeat();
    } catch (e) {
      debugPrint('[WsClient] Connection failed: $e');
      _setConnectionState(WsConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    _lastMessageAt = DateTime.now();
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = BackendEvent.fromJson(data);

      // Auto-pong heartbeats
      if (event.type == BackendEventType.heartbeat) {
        sendPong();
        return; // don't emit heartbeats to consumers
      }

      // Deduplication
      if (event.eventId.isNotEmpty) {
        if (_seenEventIds.contains(event.eventId)) {
          debugPrint('[WsClient] Duplicate event ignored: ${event.eventId}');
          return;
        }
        _seenEventIds.add(event.eventId);
        if (_seenEventIds.length > _dedupeSize) {
          _seenEventIds.remove(_seenEventIds.first);
        }
      }

      if (!_eventController.isClosed) {
        debugPrint('[DIAG][WsClient] Message received: type=${event.type.value}, rideId=${event.rideId}, eventId=${event.eventId}');
        _eventController.add(event);
      }
    } catch (e) {
      debugPrint('[WsClient] Failed to parse message: $e\nRaw: $raw');
    }
  }

  void _onError(Object error) {
    debugPrint('[WsClient] Stream error: $error');
    _lastError = error.toString();
    _setConnectionState(WsConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WsClient] Connection closed (intentional=$_intentionalDisconnect)');
    _cancelTimers();
    if (!_intentionalDisconnect && !_disposed) {
      _setConnectionState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  // ── Heartbeat ─────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: AppConfig.wsHeartbeatIntervalSeconds),
      (_) => sendPing(),
    );
  }

  // ── Reconnect ─────────────────────────────────────────────────────────────

  void _scheduleReconnect() {
    if (_intentionalDisconnect || _disposed) return;
    _reconnectTimer?.cancel();

    final backoffSeconds = math.min(
      math.pow(2, _reconnectAttempts).toInt(),
      AppConfig.wsMaxBackoffSeconds,
    );
    _reconnectAttempts++;

    debugPrint('[WsClient] Reconnecting in ${backoffSeconds}s (attempt $_reconnectAttempts)');
    _setConnectionState(WsConnectionState.reconnecting);

    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () async {
      if (_disposed || _intentionalDisconnect) return;
      // Refresh Firebase token before reconnecting (it may have expired)
      try {
        await _auth?.currentUser?.getIdToken(true); // force refresh
      } catch (_) {}
      await _doConnect();
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> message) {
    if (_channel != null && _connectionState == WsConnectionState.connected) {
      try {
        _channel!.sink.add(jsonEncode(message));
      } catch (e) {
        debugPrint('[WsClient] Send failed: $e');
      }
    }
  }

  void _setConnectionState(WsConnectionState newState) {
    if (_connectionState == newState) return;
    _connectionState = newState;
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    _channelSub?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    _eventController.close();
    super.dispose();
  }
}
