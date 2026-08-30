import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/backend_event.dart';

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

