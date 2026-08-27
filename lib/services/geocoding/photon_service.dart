import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../config/app_config.dart';

// ── Result model ──────────────────────────────────────────────────────────────

/// A single geocoding result from the Photon API.
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

  factory PhotonResult.fromFeature(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
    final coords = geometry['coordinates'] as List<dynamic>? ?? [];

    final name = props['name'] as String? ?? '';
    final city = props['city'] as String?;
    final state = props['state'] as String?;
    final country = props['country'] as String?;

    // Build a human-readable label from available parts
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

/// Provides destination autocomplete using the Photon geocoding API.
///
/// Features:
/// - 300ms debounce (configurable via [AppConfig.photonDebounceMs])
/// - In-memory result cache (5 min TTL)
/// - Request cancellation via generation counter
/// - Kerala/Kollam geographic bias
/// - Never throws to the caller — returns empty list on error
/// - Never exposes the server URL in UI code
///
/// Used exclusively by [DestinationSearchBar] for the passenger destination
/// search feature. Does NOT interact with any ride, booking, or matching logic.
class PhotonService {
  late final Dio _dio;

  // Request generation counter — incremented on each new search.
  // If a response arrives for an older generation, it is discarded.
  int _generation = 0;

  // Debounce timer
  Timer? _debounceTimer;

  // Simple in-memory cache
  final Map<String, _CacheEntry> _cache = {};

  PhotonService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.photonUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'MyAuto/1.0 (flutter)',
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
  ///
  /// Returns up to [AppConfig.photonMaxResults] results.
  /// Returns an empty list on network errors, empty input, or no results.
  ///
  /// Results are biased toward the Kerala/Kollam region.
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
        // Configurable bounding box bias via AppConfig.photonBbox
        'bbox': AppConfig.photonBbox,
        'lang': 'en',
      };

      // Add location bias if provided
      if (nearLocation != null) {
        queryParams['lon'] = nearLocation.longitude;
        queryParams['lat'] = nearLocation.latitude;
      }

      final response = await _dio.get('/api', queryParameters: queryParams);

      // Discard stale response
      if (myGeneration != _generation) {
        debugPrint('[Photon] Stale response discarded (gen=$myGeneration)');
        return [];
      }

      final data = response.data as Map<String, dynamic>?;
      final features = data?['features'] as List<dynamic>? ?? [];

      final results = features
          .whereType<Map<String, dynamic>>()
          .map((f) => PhotonResult.fromFeature(f))
          .where((r) => r.displayLabel.isNotEmpty)
          .toList();

      // Cache results
      _cache[trimmed] = _CacheEntry(results);

      debugPrint('[Photon] "$trimmed" → ${results.length} results');
      return results;
    } on DioException catch (e) {
      debugPrint('[Photon] Network error for "$trimmed": ${e.message}');
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
    _generation++; // invalidate any in-flight request
  }

  /// Dispose the service and free resources.
  void dispose() {
    _debounceTimer?.cancel();
    _dio.close();
  }

  // ── Cache management ──────────────────────────────────────────────────────

  /// Remove all expired cache entries.
  void pruneCache() {
    _cache.removeWhere((_, entry) => entry.isExpired);
  }

  /// Clear the entire cache.
  void clearCache() => _cache.clear();
}

// ── Provider-friendly singleton factory ───────────────────────────────────────

/// Creates a [PhotonService] instance suitable for use with Riverpod.
/// Call [PhotonService.dispose] in the provider's onDispose callback.
PhotonService createPhotonService() => PhotonService();
