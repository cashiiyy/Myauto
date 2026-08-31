import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../providers/destination_provider.dart';
import '../../../providers/location_provider.dart';
import '../providers/map_controller_provider.dart';
import '../providers/map_provider.dart';
import '../utils/map_bounds_utils.dart';
import 'map_error_widget.dart';

/// Isolated, high-performance Google Maps widget for MyAuto.
///
/// **LIFECYCLE & PERFORMANCE GUARANTEES**:
/// 1. Owns its [GoogleMapController] locally — the native controller is NEVER exposed to Riverpod.
/// 2. Consumes camera commands reactively via [cameraIntentProvider] (Camera Intent architecture).
/// 3. Isolates marker and polyline state changes so real-time GPS packets do NOT rebuild HomeScreen.
/// 4. Decoupled from backend connectivity — map renders independently of FastAPI / WebSocket state.
class MyAutoGoogleMap extends ConsumerStatefulWidget {
  final VoidCallback? onTap;
  final LatLng initialCenter;
  final double initialZoom;

  const MyAutoGoogleMap({
    super.key,
    this.onTap,
    this.initialCenter = const LatLng(8.5241, 76.9366), // Default Trivandrum / Kerala
    this.initialZoom = 15.0,
  });

  @override
  ConsumerState<MyAutoGoogleMap> createState() => _MyAutoGoogleMapState();
}

class _MyAutoGoogleMapState extends ConsumerState<MyAutoGoogleMap> {
  GoogleMapController? _controller;
  bool _hasMapError = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    debugPrint('[MyAutoGoogleMap] GoogleMapController initialized locally.');
  }

  void _onCameraIdle() {
    // Viewport idle hook for future spatial indexing / bounding box queries
    // Does NOT trigger REST or WebSocket queries on every minor pan/zoom
  }

  Future<void> _handleCameraRequest(CameraRequest request) async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    try {
      switch (request.type) {
        case CameraRequestType.animateTo:
          if (request.target != null) {
            await controller.animateCamera(
              CameraUpdate.newLatLngZoom(request.target!, request.zoom),
            );
          }
          break;
        case CameraRequestType.moveTo:
          if (request.target != null) {
            await controller.moveCamera(
              CameraUpdate.newLatLngZoom(request.target!, request.zoom),
            );
          }
          break;
        case CameraRequestType.fitBounds:
          if (request.bounds != null) {
            await controller.animateCamera(
              CameraUpdate.newLatLngBounds(request.bounds!, request.padding),
            );
          }
          break;
      }
    } catch (e) {
      debugPrint('[MyAutoGoogleMap] Camera request failed: $e');
    } finally {
      // Clear intent once consumed so it doesn't re-trigger
      if (mounted) {
        ref.read(cameraIntentProvider.notifier).state = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasMapError) {
      return MapErrorWidget(
        message: _errorMessage,
        onRetry: () => setState(() {
          _hasMapError = false;
          _errorMessage = null;
        }),
      );
    }

    // ── Listen to Camera Intents ─────────────────────────────────────────────
    ref.listen<CameraRequest?>(cameraIntentProvider, (prev, next) {
      if (next != null && mounted) {
        _handleCameraRequest(next);
      }
    });

    // ── Listen to Route changes to automatically fit camera bounds ───────────
    ref.listen<AsyncValue<dynamic>>(routeProvider, (prev, next) {
      final route = next.value;
      if (route != null && mounted) {
        final posAsync = ref.read(currentLocationProvider);
        final dest = ref.read(destinationProvider);
        if (posAsync.value != null && dest != null) {
          final pos = LatLng(posAsync.value!.latitude, posAsync.value!.longitude);
          final destPos = LatLng(dest.latitude, dest.longitude);
          final bounds = boundsFromPoints([pos, destPos, ...route.polyline]);
          if (bounds != null) {
            _handleCameraRequest(CameraRequest.fitBounds(bounds, padding: 60.0));
          }
        }
      }
    });

    // ── Watch visual layers ──────────────────────────────────────────────────
    final markers = ref.watch(markersProvider);
    final polylines = ref.watch(polylineProvider);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialCenter,
        zoom: widget.initialZoom,
      ),
      onMapCreated: _onMapCreated,
      onCameraIdle: _onCameraIdle,
      onTap: (_) {
        if (widget.onTap != null) widget.onTap!();
      },
      markers: markers,
      polylines: polylines,
      myLocationEnabled: false, // We render a custom high-res vehicle/user marker
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
      buildingsEnabled: true,
      trafficEnabled: false,
    );
  }
}
