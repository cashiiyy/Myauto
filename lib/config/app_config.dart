/// MyAuto backend and mobile client configuration.
///
/// All backend URLs are injected via --dart-define at build time.
///
/// Development / Private Admin (Tailscale):
///   flutter run --dart-define=BACKEND_URL=http://100.89.251.123:8919 \
///               --dart-define=BACKEND_WS_URL=ws://100.89.251.123:8919/ws
///
/// Production (Public HTTPS/WSS behind Reverse Proxy / Caddy):
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
    defaultValue: 'https://faculty-employee-shuffling.ngrok-free.dev',
  );

  // ── Build Identity ────────────────────────────────────────────────────────
  static const String buildTimestamp = String.fromEnvironment(
    'BUILD_TIMESTAMP',
    defaultValue: 'Unknown (IDE/Local)',
  );

  static const String gitCommit = String.fromEnvironment(
    'GIT_COMMIT',
    defaultValue: 'Unknown',
  );

  // ── Backend WebSocket URL ─────────────────────────────────────────────────
  static const String backendWsUrl = String.fromEnvironment(
    'BACKEND_WS_URL',
    defaultValue: 'wss://faculty-employee-shuffling.ngrok-free.dev/ws',
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

  // ── Map rendering mode & tiles ────────────────────────────────────────────
  /// Controls which map renderer is used.
  /// 'flutter_map' (default) — uses flutter_map + high-res styled tiles.
  /// 'maplibre'             — uses MapLibre GL vector tiles (requires vector style URL).
  static const String mapMode = String.fromEnvironment(
    'MAP_MODE',
    defaultValue: 'flutter_map',
  );

  /// MapLibre style JSON URL. Only used when mapMode == 'maplibre'.
  static const String mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://demotiles.maplibre.org/style.json',
  );

  /// High-resolution CartoDB Voyager styled map tile template.
  /// Clean, modern, high-contrast city map rendering.
  static const String tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
  );

  // ── Real-time transport mode ──────────────────────────────────────────────
  /// Controls which real-time transport layer is used.
  /// 'websocket' (default & production standard) — FastAPI Native WebSocket.
  /// 'mock' — mock events for offline development.
  static const String realtimeMode = String.fromEnvironment(
    'REALTIME_MODE',
    defaultValue: 'websocket',
  );

  // ── Geocoding (Photon via Backend Proxy) ──────────────────────────────────
  /// Base URL for the Photon geocoding API.
  static const String photonUrl = String.fromEnvironment(
    'PHOTON_URL',
    defaultValue: 'https://photon.komoot.io',
  );

  /// Bounding box for Photon geocoding bias (Kollam district).
  static const String photonBbox = String.fromEnvironment(
    'PHOTON_BBOX',
    defaultValue: '76.35,8.70,76.85,9.10',
  );

  /// Debounce delay in milliseconds for autocomplete requests.
  static const int photonDebounceMs = 300;

  /// Maximum number of autocomplete results to display.
  static const int photonMaxResults = 5;

  // ── Routing (Valhalla) ────────────────────────────────────────────────────
  static const String valhallaUrl = String.fromEnvironment(
    'VALHALLA_URL',
    defaultValue: 'https://valhalla1.openstreetmap.de',
  );

  static const String valhallaCosting = String.fromEnvironment(
    'VALHALLA_COSTING',
    defaultValue: 'auto',
  );
}
