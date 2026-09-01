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

  // ── Canvas-based crisp vector icon generation ──────────────────────────────

  Future<BitmapDescriptor> _createRickshawMarker({
    required Color badgeColor,
    required Color borderColor,
    required bool isSelected,
  }) async {
    final size = isSelected ? 128.0 : 104.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final center = Offset(size / 2, size / 2);
    final radius = (size / 2) - 8;

    // 1. Soft drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isSelected ? 0.35 : 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 8 : 5);
    canvas.drawCircle(center + const Offset(0, 4), radius, shadowPaint);

    // 2. Outer pulse / selection glow ring (if selected)
    if (isSelected) {
      final glowPaint = Paint()
        ..color = badgeColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0;
      canvas.drawCircle(center, radius + 3, glowPaint);
    }

    // 3. Base disc background (pure crisp white)
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius, bgPaint);

    // 4. Inner subtle status tint
    final tintPaint = Paint()..color = badgeColor.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius - 2, tintPaint);

    // 5. Outer border ring
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 4.5 : 3.0;
    canvas.drawCircle(center, radius, borderPaint);

    // 6. Vector Auto Rickshaw Drawing (Iconic Kerala Auto silhouette)
    final scale = size / 104.0;
    canvas.save();
    canvas.translate(center.dx - (26 * scale), center.dy - (20 * scale));
    canvas.scale(scale);

    _drawVectorRickshaw(canvas, badgeColor);

    canvas.restore();

    // 7. Status badge indicator dot at top-right
    final badgeCenter = Offset(center.dx + radius * 0.62, center.dy - radius * 0.62);
    final badgeBg = Paint()..color = Colors.white;
    canvas.drawCircle(badgeCenter, 8.5 * scale, badgeBg);

    final statusDot = Paint()..color = badgeColor;
    canvas.drawCircle(badgeCenter, 6.5 * scale, statusDot);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// Draws a clean, recognizable Auto-Rickshaw vector shape.
  void _drawVectorRickshaw(Canvas canvas, Color statusColor) {
    // ── Ground shadow under tires ──
    final groundShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawOval(const Rect.fromLTWH(2, 34, 48, 6), groundShadow);

    // ── Rear Tire ──
    final tirePaint = Paint()..color = const Color(0xFF1F2937);
    canvas.drawCircle(const Offset(12, 32), 6.5, tirePaint);
    final rimPaint = Paint()..color = const Color(0xFFE5E7EB);
    canvas.drawCircle(const Offset(12, 32), 3.5, rimPaint);
    final hubPaint = Paint()..color = const Color(0xFF4B5563);
    canvas.drawCircle(const Offset(12, 32), 1.5, hubPaint);

    // ── Front Tire ──
    canvas.drawCircle(const Offset(42, 32), 6.5, tirePaint);
    canvas.drawCircle(const Offset(42, 32), 3.5, rimPaint);
    canvas.drawCircle(const Offset(42, 32), 1.5, hubPaint);

    // ── Main Lower Chassis / Body (Kerala Auto Dark Green / Black) ──
    final bodyPath = Path()
      ..moveTo(4, 28)
      ..lineTo(4, 20)
      ..lineTo(14, 20)
      ..lineTo(18, 16)
      ..lineTo(38, 16)
      ..lineTo(46, 22)
      ..lineTo(48, 28)
      ..lineTo(46, 30)
      ..lineTo(6, 30)
      ..close();

    final bodyPaint = Paint()..color = const Color(0xFF0F766E); // Deep Kerala emerald/teal green
    canvas.drawPath(bodyPath, bodyPaint);

    // Chassis accent line (Yellow stripe)
    final stripePaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(6, 26), const Offset(46, 26), stripePaint);

    // ── Canopy / Hood (Iconic Auto Yellow) ──
    final canopyPath = Path()
      ..moveTo(2, 18)
      ..cubicTo(2, 10, 10, 4, 22, 4)
      ..lineTo(34, 4)
      ..cubicTo(40, 4, 44, 8, 45, 12)
      ..lineTo(44, 15)
      ..lineTo(2, 18)
      ..close();

    final canopyPaint = Paint()..color = const Color(0xFFF59E0B); // Vibrant rich auto yellow
    canvas.drawPath(canopyPath, canopyPaint);

    // Canopy highlight (gloss curve)
    final canopyHighlight = Path()
      ..moveTo(6, 12)
      ..cubicTo(10, 7, 18, 6, 30, 6)
      ..lineTo(38, 6);
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(canopyHighlight, highlightPaint);

    // Canopy rear trim (Black soft top curve)
    final rearTrimPaint = Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(2, 18), const Offset(4, 12), rearTrimPaint);

    // ── Windshield (Sky Blue Glass with Reflection) ──
    final windshieldPath = Path()
      ..moveTo(34, 6)
      ..lineTo(43, 14)
      ..lineTo(39, 18)
      ..lineTo(30, 18)
      ..close();

    final glassPaint = Paint()..color = const Color(0xFFBAE6FD);
    canvas.drawPath(windshieldPath, glassPaint);

    // Glass gloss reflection
    final glassShine = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(35, 9), const Offset(39, 15), glassShine);

    // ── Front Pillar / Handlebar Frame ──
    final framePaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(43, 14), const Offset(46, 26), framePaint);
    canvas.drawLine(const Offset(30, 18), const Offset(28, 28), framePaint);

    // ── Front Headlight (Warm Golden Beam) ──
    final headlightPaint = Paint()..color = const Color(0xFFFEF08A);
    canvas.drawCircle(const Offset(47, 24), 2.5, headlightPaint);
    final headlightTrim = Paint()
      ..color = const Color(0xFF4B5563)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(47, 24), 2.5, headlightTrim);
  }

  Future<BitmapDescriptor> _createDestinationPinMarker() async {
    const width = 88.0;
    const height = 104.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    const center = Offset(44, 38);

    // Ground shadow at tip
    final tipShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(const Rect.fromLTWH(30, 92, 28, 8), tipShadow);

    // Pin Body Path
    final pinPath = Path()
      ..moveTo(44, 98)
      ..cubicTo(26, 70, 16, 52, 16, 38)
      ..cubicTo(16, 22.5, 28.5, 10, 44, 10)
      ..cubicTo(59.5, 10, 72, 22.5, 72, 38)
      ..cubicTo(72, 52, 62, 70, 44, 98)
      ..close();

    // Red Gradient Fill
    final pinPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(44, 10),
        const Offset(44, 98),
        [const Color(0xFFEF4444), const Color(0xFFDC2626)],
      );
    canvas.drawPath(pinPath, pinPaint);

    // White outline
    final outlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawPath(pinPath, outlinePaint);

    // Inner White Disc
    final innerDisc = Paint()..color = Colors.white;
    canvas.drawCircle(center, 13.0, innerDisc);

    // Inner Red Center Dot
    final innerDot = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(center, 7.5, innerDot);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createUserLocationMarker() async {
    const size = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    const center = Offset(size / 2, size / 2);

    // 1. Soft pulsing radar halo
    final haloPaint = Paint()..color = const Color(0xFF3B82F6).withValues(alpha: 0.22);
    canvas.drawCircle(center, 34, haloPaint);

    final middleRing = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 24, middleRing);

    // 2. Crisp white border disc with shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + const Offset(0, 2), 15, shadowPaint);

    final borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 15, borderPaint);

    // 3. Vibrant blue core dot
    final corePaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        11,
        [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
      );
    canvas.drawCircle(center, 11, corePaint);

    // 4. Central pinpoint highlight
    final shinePaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(center - const Offset(3, 3), 2.5, shinePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createRideShareMarker() async {
    const size = 88.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    const center = Offset(size / 2, size / 2);

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center + const Offset(0, 3), 30, shadowPaint);

    // Teal Base
    final bgPaint = Paint()..color = const Color(0xFF0D9488);
    canvas.drawCircle(center, 30, bgPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(center, 30, borderPaint);

    // Two-person sharing vector icon
    final personPaint = Paint()..color = Colors.white;
    // Left person
    canvas.drawCircle(const Offset(37, 36), 4.5, personPaint);
    final leftBody = Path()
      ..moveTo(30, 50)
      ..cubicTo(30, 44, 34, 43, 37, 43)
      ..cubicTo(40, 43, 44, 44, 44, 50)
      ..close();
    canvas.drawPath(leftBody, personPaint);

    // Right person
    canvas.drawCircle(const Offset(51, 36), 4.5, personPaint);
    final rightBody = Path()
      ..moveTo(44, 50)
      ..cubicTo(44, 44, 48, 43, 51, 43)
      ..cubicTo(54, 43, 58, 44, 58, 50)
      ..close();
    canvas.drawPath(rightBody, personPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createIncomingRequestMarker() async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    const center = Offset(size / 2, size / 2);

    final haloPaint = Paint()..color = Colors.amber.withValues(alpha: 0.3);
    canvas.drawCircle(center, 40, haloPaint);

    final bgPaint = Paint()..color = const Color(0xFFD97706);
    canvas.drawCircle(center, 28, bgPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(center, 28, borderPaint);

    // Person silhouette pickup icon
    final iconPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(48, 40), 5.5, iconPaint);
    final body = Path()
      ..moveTo(39, 58)
      ..cubicTo(39, 49, 43, 48, 48, 48)
      ..cubicTo(53, 48, 57, 49, 57, 58)
      ..close();
    canvas.drawPath(body, iconPaint);

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
