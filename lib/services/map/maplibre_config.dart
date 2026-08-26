import '../../config/app_config.dart';

/// MapLibre-specific configuration constants.
///
/// These values are only read when [AppConfig.mapMode] == 'maplibre'.
/// When using the default flutter_map mode, this file has no effect.
///
/// Style URL precedence:
///   1. --dart-define=MAP_STYLE_URL=<url>   (production / custom)
///   2. [kDemoStyleUrl]                      (development fallback)
///
/// To use a self-hosted tile server with a Kerala/Kollam extract:
///   --dart-define=MAP_STYLE_URL=http://YOUR_SERVER/styles/osm-bright/style.json
///   --dart-define=TILE_URL=http://YOUR_SERVER/tiles/{z}/{x}/{y}.pbf
class MapLibreConfig {
  MapLibreConfig._();

  /// MapLibre public demo style (OpenMapTiles / OSM-compatible).
  /// Suitable for development only — no SLA, no rate limit guarantee.
  static const String kDemoStyleUrl = 'https://demotiles.maplibre.org/style.json';

  /// OpenFreeMap Versatiles style — OSM-based, no API key required.
  /// Recommended over demo tiles for better performance.
  static const String kOpenFreeMapStyle =
      'https://tiles.openfreemap.org/styles/liberty';

  /// Active style URL — reads from AppConfig (env-injected) first,
  /// then falls back to the OpenFreeMap style for development.
  static String get activeStyleUrl {
    final configured = AppConfig.mapStyleUrl;
    // If the user did not override MAP_STYLE_URL, use OpenFreeMap
    if (configured == 'https://demotiles.maplibre.org/style.json') {
      return kOpenFreeMapStyle;
    }
    return configured;
  }

  // ── Default camera bounds for Kerala / Kollam region ─────────────────────

  /// Centre of Kollam city — used as the default map centre for regional
  /// Photon and Valhalla queries.
  static const double kollumLat = 8.8932;
  static const double kollumLng = 76.6141;

  /// Kollam district bounding box for geocoding bias (tight — MyAuto service area).
  /// [west, south, east, north]
  /// Covers: Kollam city, Karunagappally, Kottarakkara, Punalur and nearby towns.
  static const List<double> kollumBbox = [76.35, 8.70, 76.85, 9.10];

  /// Broader Kerala bounding box — use when kollumBbox returns no results.
  static const List<double> keralaBbox = [76.0, 8.0, 77.5, 12.0];

  // ── MapLibre attribution ──────────────────────────────────────────────────
  static const String osmAttribution =
      '© OpenStreetMap contributors, © MapLibre';
}
