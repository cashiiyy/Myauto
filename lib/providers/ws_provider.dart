import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/backend/ws_client.dart';
import '../services/realtime/realtime_adapter.dart';
import '../models/backend_event.dart';

export '../services/backend/ws_client.dart';

/// Singleton [BackendWebSocketClient].
///
/// The client is created once and auto-connects when the user is authenticated.
/// The Riverpod container keeps it alive for the app lifetime.
final wsClientProvider = Provider<BackendWebSocketClient>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final client = BackendWebSocketClient(auth: auth);

  // Auto-connect when the user becomes authenticated
  ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
    final user = next.valueOrNull;
    if (user != null) {
      client.connect();
    } else {
      client.disconnect();
    }
  });

  // Initial connect if already authenticated
  final currentUser = ref.read(authStateProvider).valueOrNull;
  if (currentUser != null) {
    Future.microtask(() => client.connect());
  }

  ref.onDispose(client.dispose);
  return client;
});

/// Exposes the current WebSocket connection state as a stream.
final wsConnectionStateProvider = StreamProvider<WsConnectionState>((ref) {
  final client = ref.watch(wsClientProvider);
  return Stream<WsConnectionState>.periodic(
    const Duration(milliseconds: 500),
    (_) => client.connectionState,
  ).distinct();
});

/// Broadcasts all non-heartbeat events from the backend WebSocket.
final backendEventsProvider = StreamProvider<BackendEvent>((ref) {
  final client = ref.watch(wsClientProvider);
  return client.events;
});

// ── New: Realtime Adapter Provider ────────────────────────────────────────────
//
// This provider selects the real-time transport layer based on REALTIME_MODE.
//
// REALTIME_MODE=websocket (default):
//   Returns null — callers continue using the existing wsClientProvider /
//   BackendWebSocketClient path. Zero behaviour change.
//
// REALTIME_MODE=socketio:
//   Returns a SocketIoRealtimeAdapter that connects to the Node.js server.
//
// REALTIME_MODE=mock:
//   Returns a MockRealtimeAdapter that emits no events.

/// The active [RealtimeAdapter].
final realtimeAdapterProvider = Provider<RealtimeAdapter>((ref) {
  final adapter = createRealtimeAdapter();
  ref.onDispose(adapter.dispose);
  // Connect after the first frame to avoid build-phase side-effects
  Future.microtask(() => adapter.connect());
  return adapter;
});

/// Unified backend events stream.
final mergedBackendEventsProvider = StreamProvider<BackendEvent>((ref) {
  final adapter = ref.watch(realtimeAdapterProvider);
  return adapter.events;
});

