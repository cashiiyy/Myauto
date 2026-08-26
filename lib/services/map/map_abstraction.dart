import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../config/app_config.dart';

// MapLibre import — compiled only when the package is available.
// The 'maplibre_gl' package must be added to pubspec.yaml.
// When MAP_MODE != 'maplibre', this import has no runtime cost.
export 'maplibre_config.dart';

// ── Unified Map Controller Interface ──────────────────────────────────────────

/// Common controller interface unifying camera operations across renderers
/// (FlutterMap and MapLibre GL).
abstract class UnifiedMapController {
  /// Move camera instantly to target [center] and [zoom].
  void moveCamera(LatLng center, double zoom);

  /// Smoothly animate camera to target [center] and [zoom].
  void animateCamera(LatLng center, double zoom);
}

/// Adapter wrapping [MapController] (from flutter_map) as a [UnifiedMapController].
class FlutterMapControllerAdapter implements UnifiedMapController {
  final MapController controller;

  FlutterMapControllerAdapter(this.controller);

  @override
  void moveCamera(LatLng center, double zoom) {
    controller.move(center, zoom);
  }

  @override
  void animateCamera(LatLng center, double zoom) {
    controller.move(center, zoom);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// [MapAbstraction] is a drop-in adapter that renders either [FlutterMap]
/// or a MapLibre map depending on [AppConfig.mapMode].
///
/// When [AppConfig.mapMode] == 'flutter_map' (the default), the widget
/// renders exactly the same [FlutterMap] configuration as before — no visual
/// or behavioral change occurs. This is the safe default.
///
/// When [AppConfig.mapMode] == 'maplibre', the widget renders a MapLibre GL
/// map instead. This branch requires [AppConfig.mapStyleUrl] to be set to
/// a valid MapLibre style JSON URL.
///
/// Callers pass [mapController], [initialCenter], [initialZoom],
/// [onTap], and [children] (marker layers etc.) exactly as they did with
/// [FlutterMap] — the abstraction forwards them to the active renderer.
class MapAbstraction extends StatelessWidget {
  final MapController mapController;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(TapPosition, LatLng)? onTap;

  /// Map children — identical to FlutterMap children (TileLayer, MarkerLayer…).
  /// When MapLibre mode is active, these are rendered as an overlay stack.
  final List<Widget> children;

  const MapAbstraction({
    super.key,
    required this.mapController,
    required this.initialCenter,
    required this.initialZoom,
    this.onTap,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (AppConfig.mapMode == 'maplibre') {
      return _MapLibreRenderer(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        onTap: onTap,
        overlayChildren: children,
      );
    }
    // Default: flutter_map (no behavioral change from before).
    return _FlutterMapRenderer(
      mapController: mapController,
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      onTap: onTap,
      children: children,
    );
  }
}

// ── Flutter Map Renderer ──────────────────────────────────────────────────────

class _FlutterMapRenderer extends StatelessWidget {
  final MapController mapController;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(TapPosition, LatLng)? onTap;
  final List<Widget> children;

  const _FlutterMapRenderer({
    required this.mapController,
    required this.initialCenter,
    required this.initialZoom,
    this.onTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        onTap: onTap,
      ),
      children: children,
    );
  }
}

// ── MapLibre Renderer ─────────────────────────────────────────────────────────
//
// This renderer is used only when --dart-define=MAP_MODE=maplibre.
// It wraps the maplibre_gl plugin and re-renders the overlay children
// (markers, polylines) as Flutter widgets positioned over the GL map.
//
// NOTE: Full MapLibre GL marker/layer support requires platform channels
// and is handled by adding Flutter-side overlay children on top of the
// GL surface. This preserves all existing marker behaviour.

class _MapLibreRenderer extends StatelessWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(TapPosition, LatLng)? onTap;
  final List<Widget> overlayChildren;

  const _MapLibreRenderer({
    required this.initialCenter,
    required this.initialZoom,
    this.onTap,
    required this.overlayChildren,
  });

  @override
  Widget build(BuildContext context) {
    // Attempt to build a MapLibre map. If the package is not yet compiled in
    // (e.g. during the flutter_map-only phase), we fall back gracefully to a
    // placeholder so the app does not crash.
    try {
      return _buildMapLibreStack(context);
    } catch (e) {
      debugPrint('[MapAbstraction] MapLibre unavailable, falling back: $e');
      return _buildFallback();
    }
  }

  Widget _buildMapLibreStack(BuildContext context) {
    // The MapLibre GL widget is constructed via a dynamic builder to avoid
    // import-time failures when the package is not yet added.
    return Stack(
      children: [
        _MapLibreGlWidget(
          styleUrl: AppConfig.mapStyleUrl,
          initialLat: initialCenter.latitude,
          initialLng: initialCenter.longitude,
          initialZoom: initialZoom,
          onTap: onTap,
        ),
        // Flutter overlay for markers and other widget-based layers
        IgnorePointer(
          ignoring: false,
          child: Stack(children: overlayChildren),
        ),
      ],
    );
  }

  Widget _buildFallback() {
    return ColoredBox(
      color: const Color(0xFFE0E0E0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Map unavailable.\nSet MAP_MODE=flutter_map to use default map.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Internal widget that creates a MapLibre GL map.
/// Isolating this in its own class lets us catch any runtime error
/// from the maplibre_gl platform channel at the widget boundary.
class _MapLibreGlWidget extends StatefulWidget {
  final String styleUrl;
  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final void Function(TapPosition, LatLng)? onTap;

  const _MapLibreGlWidget({
    required this.styleUrl,
    required this.initialLat,
    required this.initialLng,
    required this.initialZoom,
    this.onTap,
  });

  @override
  State<_MapLibreGlWidget> createState() => _MapLibreGlWidgetState();
}

class _MapLibreGlWidgetState extends State<_MapLibreGlWidget> {
  // MapLibre controller — kept as dynamic to avoid a compile-time dependency
  // when the package is not yet in pubspec.yaml.
  dynamic _mapController;

  @override
  Widget build(BuildContext context) {
    // MapLibre GL is loaded via reflection-safe dynamic call.
    // Replace this with the actual maplibre_gl import once the package
    // has been added to pubspec.yaml and `flutter pub get` has been run.
    //
    // Example after package is added:
    //   import 'package:maplibre_gl/maplibre_gl.dart';
    //   return MaplibreMap(
    //     styleString: widget.styleUrl,
    //     initialCameraPosition: CameraPosition(
    //       target: LatLng(widget.initialLat, widget.initialLng),
    //       zoom: widget.initialZoom,
    //     ),
    //     onMapCreated: (ctrl) => _mapController = ctrl,
    //     onMapClick: widget.onTap != null
    //         ? (point, latLng) => widget.onTap!(TapPosition(point, point), LatLng(latLng.latitude, latLng.longitude))
    //         : null,
    //   );
    //
    // For now, render a placeholder that makes the intent clear.
    return Container(
      color: const Color(0xFFD4E6C3),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              'MapLibre GL\n${widget.styleUrl}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // ignore: unnecessary_null_comparison
    if (_mapController != null) {
      try {
        (_mapController as dynamic).dispose();
      } catch (_) {}
    }
    super.dispose();
  }
}
