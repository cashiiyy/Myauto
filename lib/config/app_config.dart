/// MyAuto backend configuration.
///
/// All backend URLs are injected via --dart-define at build time.
/// See .env.example at the project root for the full list.
///
/// Development (Tailscale):
///   flutter run --dart-define=BACKEND_URL=http://100.89.251.123:8919 \
///               --dart-define=BACKEND_WS_URL=ws://100.89.251.123:8919/ws
///
/// Production (HTTPS/WSS behind reverse proxy):
///   flutter build apk \
///               --dart-define=BACKEND_URL=https://api.myauto.app \
///               --dart-define=BACKEND_WS_URL=wss://api.myauto.app/ws \
///               --dart-define=MOCK_MODE=false
///
/// Android emulator → host machine:
///   --dart-define=BACKEND_URL=http://10.0.2.2:8919
class AppConfig {
  AppConfig._();

  // ── Backend HTTP base URL ─────────────────────────────────────────────────
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:8919',
  );

  // ── Backend WebSocket URL ─────────────────────────────────────────────────
  static const String backendWsUrl = String.fromEnvironment(
    'BACKEND_WS_URL',
    defaultValue: 'ws://10.0.2.2:8919/ws',
  );

  // ── Mock mode bypass ─────────────────────────────────────────────────────
  /// When true, backend calls are skipped and mock data is returned.
  /// Set via --dart-define=MOCK_MODE=true for local UI development.
  static const bool mockMode = bool.fromEnvironment(
    'MOCK_MODE',
    defaultValue: false,
  );

  // ── Location settings ─────────────────────────────────────────────────────
  /// Distance filter in metres — driver GPS updates are sent only when the
  /// device has moved at least this far from the last sent position.
  static const double locationDistanceFilterMeters = 5.0;

  /// Heartbeat interval in seconds — how often the WS client sends a ping.
  static const int wsHeartbeatIntervalSeconds = 20;

  /// Maximum reconnect backoff in seconds.
  static const int wsMaxBackoffSeconds = 60;

  /// Number of recent event IDs to keep in the deduplication set.
  static const int wsDeduplicationCacheSize = 200;

  // ── Nearby driver refresh ─────────────────────────────────────────────────
  /// How often to poll GET /api/drivers/nearby (seconds).
  static const int nearbyDriverPollIntervalSeconds = 5;

  /// Radius in kilometres to search for nearby drivers.
  static const double nearbyDriverRadiusKm = 2.0;
}
