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

  // ── WARNING: Feature Flag Defaults ────────────────────────────────────────
  // WARNING: Changing these defaults will alter app behavior.
  // Only change via environment variables or dart-define flags.
  // Do NOT hardcode test URLs or credentials directly into this file.
  // ──────────────────────────────────────────────────────────────────────────

  // ── Map rendering mode ────────────────────────────────────────────────────
  /// Controls which map renderer is used.
  /// 'flutter_map' (default) — uses existing flutter_map + OSM tiles (no change).
  /// 'maplibre'             — uses MapLibre GL vector tiles.
  /// Set via --dart-define=MAP_MODE=maplibre
  static const String mapMode = String.fromEnvironment(
    'MAP_MODE',
    defaultValue: 'flutter_map',
  );

  /// MapLibre style JSON URL. Only used when mapMode == 'maplibre'.
  /// Defaults to the public MapLibre demo style for development.
  static const String mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://demotiles.maplibre.org/style.json',
  );

  /// OSM raster tile URL template. Used by flutter_map and as fallback.
  static const String tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  // ── Real-time transport mode ──────────────────────────────────────────────
  /// Controls which real-time transport layer is used.
  /// 'websocket' (default) — existing FastAPI WebSocket (BackendWebSocketClient).
  /// 'socketio'            — new Node.js Socket.IO server.
  /// 'mock'                — mock events for offline development.
  /// Set via --dart-define=REALTIME_MODE=socketio
  static const String realtimeMode = String.fromEnvironment(
    'REALTIME_MODE',
    defaultValue: 'websocket',
  );

  /// Node.js Socket.IO server URL. Only used when realtimeMode == 'socketio'.
  /// Android emulator: http://10.0.2.2:3001
  /// Physical device / Tailscale: http://<SERVER_TAILSCALE_OR_LAN_IP>:3001
  static const String socketIoUrl = String.fromEnvironment(
    'SOCKETIO_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  // ── Geocoding (Photon) ────────────────────────────────────────────────────
  /// Base URL for the Photon geocoding API.
  /// Used ONLY for the passenger destination search feature.
  /// Defaults to the public photon.komoot.io endpoint for development.
  /// Override with a self-hosted instance for production.
  static const String photonUrl = String.fromEnvironment(
    'PHOTON_URL',
    defaultValue: 'https://photon.komoot.io',
  );

  /// Bounding box for Photon geocoding bias.
  /// Format: 'minLon,minLat,maxLon,maxLat' (W,S,E,N).
  /// Defaults to Kollam district (76.35,8.70,76.85,9.10).
  /// For all-Kerala search: '76.0,8.0,77.5,12.0'.
  static const String photonBbox = String.fromEnvironment(
    'PHOTON_BBOX',
    defaultValue: '76.35,8.70,76.85,9.10',
  );

  /// Debounce delay in milliseconds for Photon autocomplete requests.
  static const int photonDebounceMs = 300;

  /// Maximum number of autocomplete results to display.
  static const int photonMaxResults = 5;

  // ── Routing (Valhalla) ────────────────────────────────────────────────────
  /// Base URL for the Valhalla routing engine.
  /// Used ONLY for route/ETA calculation via RoutingService.
  /// Defaults to the public Valhalla demo endpoint for development.
  static const String valhallaUrl = String.fromEnvironment(
    'VALHALLA_URL',
    defaultValue: 'https://valhalla1.openstreetmap.de',
  );

  /// Valhalla costing model.
  /// Defaults to 'auto'. Can be set to 'motorcycle' for narrower roads / two-wheelers.
  static const String valhallaCosting = String.fromEnvironment(
    'VALHALLA_COSTING',
    defaultValue: 'auto',
  );
}
