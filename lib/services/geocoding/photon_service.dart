import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../config/app_config.dart';

// ── Result model ──────────────────────────────────────────────────────────────

/// A single geocoding result from the backend geocoding proxy / Photon API.
class PhotonResult {
  final String displayLabel;
  final String placeName;
  final double latitude;
  final double longitude;
  final String? city;
  final String? state;
  final String? country;

  const PhotonResult({
    required this.displayLabel,
    required this.placeName,
    required this.latitude,
    required this.longitude,
    this.city,
    this.state,
    this.country,
  });

  factory PhotonResult.fromJson(Map<String, dynamic> json) {
    // Check if it's the backend proxy format
    if (json.containsKey('display_name') || json.containsKey('latitude')) {
      final name = json['name'] as String? ?? '';
      final displayName = json['display_name'] as String? ?? name;
      final lat = (json['latitude'] as num?)?.toDouble() ?? 0.0;
      final lon = (json['longitude'] as num?)?.toDouble() ?? 0.0;
      return PhotonResult(
        displayLabel: displayName.isNotEmpty ? displayName : name,
        placeName: name.isNotEmpty ? name : displayName,
        latitude: lat,
        longitude: lon,
        city: json['city'] as String?,
        state: json['state'] as String?,
        country: json['country'] as String?,
      );
    }

    // GeoJSON Feature format
    final props = json['properties'] as Map<String, dynamic>? ?? {};
    final geometry = json['geometry'] as Map<String, dynamic>? ?? {};
    final coords = geometry['coordinates'] as List<dynamic>? ?? [];

    final name = props['name'] as String? ?? '';
    final city = props['city'] as String?;
    final state = props['state'] as String?;
    final country = props['country'] as String?;

    final parts = <String>[
      if (name.isNotEmpty) name,
      if (city != null && city != name) city,
      if (state != null) state,
    ];
    final label = parts.isNotEmpty ? parts.join(', ') : name;

    return PhotonResult(
      displayLabel: label,
      placeName: name,
      latitude: (coords.length >= 2 ? (coords[1] as num).toDouble() : 0.0),
      longitude: (coords.length >= 2 ? (coords[0] as num).toDouble() : 0.0),
      city: city,
      state: state,
      country: country,
    );
  }

  factory PhotonResult.fromFeature(Map<String, dynamic> feature) =>
      PhotonResult.fromJson(feature);

  @override
  String toString() =>
      'PhotonResult(label=$displayLabel, lat=$latitude, lng=$longitude)';
}

// ── Cache entry ───────────────────────────────────────────────────────────────

class _CacheEntry {
  final List<PhotonResult> results;
  final DateTime createdAt;

  _CacheEntry(this.results) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 5);
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Provides destination autocomplete proxying through the backend API.
///
/// Features:
/// - 300ms debounce (configurable via [AppConfig.photonDebounceMs])
/// - In-memory result cache (5 min TTL)
/// - Request cancellation via generation counter
/// - Kerala/Kollam geographic bias
/// - Never throws to the caller — returns empty list on error
class PhotonService {
  late final Dio _dio;

  int _generation = 0;
  Timer? _debounceTimer;
  final Map<String, _CacheEntry> _cache = {};

  PhotonService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.backendUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'MyAuto/1.0 (flutter)',
        'ngrok-skip-browser-warning': 'true',
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (o) => debugPrint('[Photon] $o'),
      ));
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Search for places matching [query].
  Future<List<PhotonResult>> search(
    String query, {
    LatLng? nearLocation,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // Check cache first
    final cached = _cache[trimmed];
    if (cached != null && !cached.isExpired) {
      debugPrint('[Photon] Cache hit for "$trimmed"');
      return cached.results;
    }

    final myGeneration = ++_generation;

    try {
      final queryParams = <String, dynamic>{
        'q': trimmed,
        'limit': AppConfig.photonMaxResults,
        'bbox': AppConfig.photonBbox,
      };

      if (nearLocation != null) {
        queryParams['lon'] = nearLocation.longitude;
        queryParams['lat'] = nearLocation.latitude;
      }

      // Route through backend geocode proxy
      final response = await _dio.get('/api/geocode/search', queryParameters: queryParams);

      if (myGeneration != _generation) {
        debugPrint('[Photon] Stale response discarded (gen=$myGeneration)');
        return [];
      }

      List<PhotonResult> results = [];
      if (response.data is List) {
        results = (response.data as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map((item) => PhotonResult.fromJson(item))
            .where((r) => r.displayLabel.isNotEmpty)
            .toList();
      } else if (response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? [];
        results = features
            .whereType<Map<String, dynamic>>()
            .map((f) => PhotonResult.fromJson(f))
            .where((r) => r.displayLabel.isNotEmpty)
            .toList();
      }

      _cache[trimmed] = _CacheEntry(results);
      debugPrint('[Photon] "$trimmed" → ${results.length} results');
      return results;
    } on DioException catch (e) {
      debugPrint('[Photon] Backend geocode error for "$trimmed": ${e.message}');
      return [];
    } catch (e) {
      debugPrint('[Photon] Unexpected error for "$trimmed": $e');
      return [];
    }
  }

  /// Cancel any pending debounced search.
  void cancelPendingSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _generation++;
  }

  /// Dispose the service and free resources.
  void dispose() {
    _debounceTimer?.cancel();
    _dio.close();
  }

  /// Remove all expired cache entries.
  void pruneCache() {
    _cache.removeWhere((_, entry) => entry.isExpired);
  }

  /// Clear the entire cache.
  void clearCache() => _cache.clear();
}

// ── Provider-friendly singleton factory ───────────────────────────────────────

PhotonService createPhotonService() => PhotonService();
