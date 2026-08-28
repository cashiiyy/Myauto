import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/backend_event.dart';
import '../../config/app_config.dart';
import '../backend/ws_client.dart';

// ── Abstract interface ────────────────────────────────────────────────────────

/// Abstract real-time transport adapter.
///
/// Implementations:
/// - [WebSocketRealtimeAdapter]  — wraps the production [BackendWebSocketClient] (FastAPI WebSocket)
/// - [MockRealtimeAdapter]       — emits mock events for offline testing
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

// ── FastAPI WebSocket Adapter ────────────────────────────────────────────────

/// Production real-time transport adapter wrapping [BackendWebSocketClient].
class WebSocketRealtimeAdapter implements RealtimeAdapter {
  final BackendWebSocketClient _client;

  WebSocketRealtimeAdapter([BackendWebSocketClient? client])
      : _client = client ?? BackendWebSocketClient();

  @override
  Stream<BackendEvent> get events => _client.events;

  @override
  Future<void> connect() async {
    await _client.connect();
  }

  @override
  Future<void> disconnect() async {
    await _client.disconnect();
  }

  @override
  void dispose() {
    _client.dispose();
  }
}

// ── Mock adapter ──────────────────────────────────────────────────────────────

/// Emits no events — used in mock/offline mode.
class MockRealtimeAdapter implements RealtimeAdapter {
  final _controller = StreamController<BackendEvent>.broadcast();

  @override
  Stream<BackendEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    debugPrint('[MockRealtime] Connected (mock mode)');
  }

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() => _controller.close();
}

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create the appropriate [RealtimeAdapter] based on [AppConfig.realtimeMode].
RealtimeAdapter createRealtimeAdapter() {
  if (AppConfig.mockMode || AppConfig.realtimeMode == 'mock') {
    return MockRealtimeAdapter();
  }
  return WebSocketRealtimeAdapter();
}
