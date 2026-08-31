import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../models/nearby_driver_model.dart';
import '../../../models/ride_share_model.dart';
import '../../../models/backend_event.dart';
import '../../../providers/destination_provider.dart';

/// Centralized marker manager for MyAuto Google Maps.
///
/// Responsibilities:
/// - Asynchronously loads and renders all marker icons once at startup into memory.
/// - Caches [BitmapDescriptor] objects to eliminate asset decoding and canvas operations
///   during real-time GPS / driver updates.
/// - Transforms normalized domain models into a high-performance [Set<Marker>].
class MarkerService {
  final Map<String, BitmapDescriptor> _iconCache = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Asynchronously generates/loads and caches all marker icons.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Available Auto Rickshaw (Green theme)
      _iconCache['auto_available'] = await _createRickshawMarker(
        badgeColor: const Color(0xFF10B981),
        borderColor: const Color(0xFF059669),
        isSelected: false,
      );

      // 2. Selected Available Auto Rickshaw
      _iconCache['auto_available_selected'] = await _createRickshawMarker(
        badgeColor: const Color(0xFF10B981),
        borderColor: Colors.black87,
        isSelected: true,
      );

      // 3. Busy Auto Rickshaw (Red theme)
      _iconCache['auto_busy'] = await _createRickshawMarker(
        badgeColor: const Color(0xFFEF4444),
        borderColor: const Color(0xFFDC2626),
        isSelected: false,
      );

      // 4. Selected Busy Auto Rickshaw
      _iconCache['auto_busy_selected'] = await _createRickshawMarker(
        badgeColor: const Color(0xFFEF4444),
        borderColor: Colors.black87,
        isSelected: true,
      );

      // 5. Destination Pin (Red accent)
      _iconCache['destination_pin'] = await _createDestinationPinMarker();

      // 6. User Location Dot (Blue theme)
      _iconCache['user_location'] = await _createUserLocationMarker();

      // 7. Co-Passenger Ride Share (Teal 🤝)
      _iconCache['ride_share'] = await _createRideShareMarker();

      // 8. Incoming Ride Request Pickup (Pulsing 🧍)
      _iconCache['incoming_request'] = await _createIncomingRequestMarker();

      _isInitialized = true;
      debugPrint('[MarkerService] Marker icons successfully cached.');
    } catch (e, st) {
      debugPrint('[MarkerService] Failed to generate marker icons: $e\n$st');
    }
  }

  /// Builds a [Set<Marker>] from real-time domain states.
  Set<Marker> buildMarkers({
    required List<NearbyDriverModel> drivers,
    required Position? currentPosition,
    required DestinationPlace? destination,
    required List<RideShareModel> rideShares,
    required BackendEvent? incomingRequest,
    required String? selectedDriverUid,
    required String userRole,
    void Function(NearbyDriverModel driver)? onDriverSelected,
    void Function(RideShareModel share)? onShareSelected,
  }) {
    final markers = <Marker>{};

    // ── 1. Own Position Marker (if GPS available) ───────────────────────────
    if (currentPosition != null && _iconCache.containsKey('user_location')) {
      markers.add(
        Marker(
          markerId: const MarkerId('myauto_user_location'),
          position: LatLng(currentPosition.latitude, currentPosition.longitude),
          icon: _iconCache['user_location']!,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 1,
          flat: true,
        ),
      );
    }

    // ── 2. Nearby Drivers (Passenger View) ──────────────────────────────────
    if (userRole == 'passenger') {
      for (final driver in drivers) {
        if (driver.isStale) continue;

        final isSelected = driver.driverUid == selectedDriverUid;
        final key = driver.isAvailable
            ? (isSelected ? 'auto_available_selected' : 'auto_available')
            : (isSelected ? 'auto_busy_selected' : 'auto_busy');

        final icon = _iconCache[key] ?? BitmapDescriptor.defaultMarker;

        markers.add(
          Marker(
            markerId: MarkerId('driver_${driver.driverUid}'),
            position: LatLng(driver.latitude, driver.longitude),
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: isSelected ? 3 : 2,
            infoWindow: InfoWindow(
              title: driver.isAvailable ? 'Available Auto' : 'Busy Auto',
              snippet: '${driver.distanceKm.toStringAsFixed(1)} km away • Rating: ${driver.rating ?? 5.0}',
            ),
            onTap: () {
              if (onDriverSelected != null) {
                onDriverSelected(driver);
              }
            },
          ),
        );
      }
    }

    // ── 3. Destination Pin (Passenger View) ─────────────────────────────────
    if (destination != null && _iconCache.containsKey('destination_pin')) {
      markers.add(
        Marker(
          markerId: const MarkerId('myauto_destination_pin'),
          position: LatLng(destination.latitude, destination.longitude),
          icon: _iconCache['destination_pin']!,
          anchor: const Offset(0.5, 0.9),
          zIndexInt: 4,
          infoWindow: InfoWindow(
            title: destination.placeName.isNotEmpty
                ? destination.placeName
                : destination.displayLabel,
            snippet: destination.displayLabel,
          ),
        ),
      );
    }

    // ── 4. Co-Passenger Ride Shares (RTDB Active Flow) ──────────────────────
    if (rideShares.isNotEmpty && _iconCache.containsKey('ride_share')) {
      for (final share in rideShares) {
        markers.add(
          Marker(
            markerId: MarkerId('share_${share.uid}'),
            position: LatLng(share.latitude, share.longitude),
            icon: _iconCache['ride_share']!,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 3,
            infoWindow: InfoWindow(
              title: '${share.name} (Sharing Ride)',
              snippet: 'Tap to connect with co-passenger',
            ),
            onTap: () {
              if (onShareSelected != null) {
                onShareSelected(share);
              }
            },
          ),
        );
      }
    }

    // ── 5. Incoming Ride Request Pickup Pulse (Driver View) ─────────────────
    if (userRole == 'driver' && incomingRequest != null) {
      final lat = (incomingRequest.payload['pickup_lat'] as num?)?.toDouble();
      final lng = (incomingRequest.payload['pickup_lng'] as num?)?.toDouble();
      if (lat != null && lng != null && _iconCache.containsKey('incoming_request')) {
        markers.add(
          Marker(
            markerId: MarkerId('incoming_request_${incomingRequest.eventId}'),
            position: LatLng(lat, lng),
            icon: _iconCache['incoming_request']!,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 5,
            infoWindow: const InfoWindow(
              title: 'Incoming Ride Request',
              snippet: 'Pickup Location',
            ),
          ),
        );
      }
    }

    return markers;
  }

  // ── Canvas-based crisp icon generation ─────────────────────────────────────

  Future<BitmapDescriptor> _createRickshawMarker({
    required Color badgeColor,
    required Color borderColor,
    required bool isSelected,
  }) async {
    final size = isSelected ? 120.0 : 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final center = Offset(size / 2, size / 2);
    final radius = (size / 2) - 8;

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center + const Offset(0, 3), radius, shadowPaint);

    // Background circle
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius, bgPaint);

    // Inner tint circle
    final tintPaint = Paint()..color = badgeColor.withValues(alpha: 0.22);
    canvas.drawCircle(center, radius - 2, tintPaint);

    // Border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 5.0 : 3.5;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw Emoji / Icon: 🛺
    final textPainter = TextPainter(
      text: TextSpan(
        text: '🛺',
        style: TextStyle(
          fontSize: isSelected ? 48.0 : 38.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createDestinationPinMarker() async {
    const width = 80.0;
    const height = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(const Offset(40, 38), 26, shadowPaint);

    final bgPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(const Offset(40, 38), 24, bgPaint);

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(const Offset(40, 38), 24, strokePaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '📍',
        style: TextStyle(fontSize: 34),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(23, 20));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createUserLocationMarker() async {
    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    const center = Offset(size / 2, size / 2);

    // Outer halo
    final haloPaint = Paint()..color = const Color(0xFF3B82F6).withValues(alpha: 0.25);
    canvas.drawCircle(center, 28, haloPaint);

    // White border ring
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 14, borderPaint);

    // Blue core dot
    final corePaint = Paint()..color = const Color(0xFF2563EB);
    canvas.drawCircle(center, 10, corePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createRideShareMarker() async {
    const size = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    const center = Offset(size / 2, size / 2);

    final bgPaint = Paint()..color = const Color(0xFF0D9488);
    canvas.drawCircle(center, 30, bgPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, 30, borderPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🤝',
        style: TextStyle(fontSize: 28),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - (textPainter.width / 2), center.dy - (textPainter.height / 2)),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createIncomingRequestMarker() async {
    const size = 88.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    const center = Offset(size / 2, size / 2);

    final haloPaint = Paint()..color = Colors.blue.withValues(alpha: 0.35);
    canvas.drawCircle(center, 38, haloPaint);

    final bgPaint = Paint()..color = const Color(0xFF1E40AF);
    canvas.drawCircle(center, 28, bgPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, 28, borderPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🧍',
        style: TextStyle(fontSize: 32),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - (textPainter.width / 2), center.dy - (textPainter.height / 2)),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }
}

/// Asynchronous singleton provider for [MarkerService].
/// Loads marker assets once and makes cached descriptors available to providers.
final markerServiceProvider = FutureProvider<MarkerService>((ref) async {
  final service = MarkerService();
  await service.initialize();
  return service;
});
