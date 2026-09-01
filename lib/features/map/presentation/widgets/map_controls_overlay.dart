import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../providers/backend_drivers_provider.dart';
import '../../../../providers/destination_provider.dart';
import '../../../../providers/location_provider.dart';
import '../../providers/map_controller_provider.dart';
import '../../providers/map_provider.dart';
import '../../utils/map_bounds_utils.dart';

/// Premium floating map control system for MyAuto Google Maps.
///
/// Features:
/// 1. Current Location Button with dynamic states (Idle, Locating, Following, Permission Denied)
/// 2. Recenter Map Button with smart target detection (User location or Route bounds)
/// 3. Driver Discovery Scan Button with vector radar icon, spin animation, and concurrency lock
/// 4. Diagnostics Button for instant live telemetry
/// 5. Emergency SOS Button with backend trigger and phone dialer fallback
class MapControlsOverlay extends ConsumerStatefulWidget {
  final String role;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onTriggerSos;
  final bool isAutoDetailsOpen;

  const MapControlsOverlay({
    super.key,
    required this.role,
    required this.onOpenDiagnostics,
    required this.onTriggerSos,
    this.isAutoDetailsOpen = false,
  });

  @override
  ConsumerState<MapControlsOverlay> createState() => _MapControlsOverlayState();
}

class _MapControlsOverlayState extends ConsumerState<MapControlsOverlay>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  late AnimationController _scanAnimController;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    super.dispose();
  }

  // ── Action Handlers ────────────────────────────────────────────────────────

  Future<void> _handleDiscoveryScan() async {
    if (_isScanning) return;

    setState(() => _isScanning = true);
    _scanAnimController.repeat();
    HapticFeedback.lightImpact();

    try {
      await ref.read(backendDriversProvider.notifier).refresh();

      if (!mounted) return;
      final driversState = ref.read(backendDriversProvider);
      final count = driversState.drivers.length;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.radar_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count > 0
                      ? 'Radar Scan: Found $count auto${count == 1 ? "" : "s"} nearby'
                      : 'Radar Scan: No autos currently nearby',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: count > 0 ? const Color(0xFF0F766E) : const Color(0xFF4B5563),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _scanAnimController.stop();
        _scanAnimController.reset();
        setState(() => _isScanning = false);
      }
    }
  }

  void _handleRecenter() {
    HapticFeedback.selectionClick();
    final pos = ref.read(currentLocationProvider).value;
    final dest = ref.read(destinationProvider);
    final routeAsync = ref.read(routeProvider);

    // If an active destination and route polyline exist, fit bounds to the entire route
    final route = routeAsync.value;
    if (pos != null && dest != null && route != null && route.polyline.isNotEmpty) {
      final userLatLng = LatLng(pos.latitude, pos.longitude);
      final destLatLng = LatLng(dest.latitude, dest.longitude);
      final bounds = boundsFromPoints([userLatLng, destLatLng, ...route.polyline]);
      if (bounds != null) {
        ref.read(cameraIntentProvider.notifier).state =
            CameraRequest.fitBounds(bounds, padding: 70.0);
        return;
      }
    }

    // Default to centering smoothly on user's GPS position
    if (pos != null) {
      ref.read(cameraIntentProvider.notifier).state = CameraRequest.animateTo(
        LatLng(pos.latitude, pos.longitude),
        zoom: 15.5,
      );
    }
  }

  Future<void> _handleLocateMe() async {
    HapticFeedback.selectionClick();
    final locationAsync = ref.read(currentLocationProvider);

    // If permission was denied or error occurred, guide user
    if (locationAsync.hasError) {
      _showPermissionGuidanceDialog();
      return;
    }

    final pos = locationAsync.value;
    if (pos != null) {
      ref.read(cameraIntentProvider.notifier).state = CameraRequest.animateTo(
        LatLng(pos.latitude, pos.longitude),
        zoom: 16.0,
      );
    } else {
      // Force refresh current location provider
      ref.invalidate(currentLocationProvider);
    }
  }

  void _showPermissionGuidanceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.location_disabled_rounded, color: Color(0xFFEF4444)),
            const SizedBox(width: 10),
            Text(
              'Location Access Required',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'MyAuto requires accurate GPS permission to discover nearby auto drivers and calculate pickup routes. Please grant location access in device settings.',
          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Geolocator.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Open Settings', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPassenger = widget.role == 'passenger';
    final locationAsync = ref.watch(currentLocationProvider);
    final isPannedAway = ref.watch(mapPannedAwayProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    // Shift down when passenger search bar is mounted at top (~72px)
    final topOffset = topPadding + (isPassenger ? 76.0 : 20.0);

    return Stack(
      children: [
        // ── Right Side Vertical Floating Controls ───────────────────────────
        Positioned(
          top: topOffset,
          right: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Discovery Scan Button (Radar / Scan nearby autos)
              _MapControlButton(
                key: const ValueKey('discovery_scan_btn'),
                tooltip: 'Scan Nearby Autos',
                backgroundColor: const Color(0xFFF0FDF4),
                borderColor: const Color(0xFF86EFAC),
                onPressed: _isScanning ? null : _handleDiscoveryScan,
                child: RotationTransition(
                  turns: _scanAnimController,
                  child: Icon(
                    Icons.radar_rounded,
                    color: _isScanning ? const Color(0xFF16A34A) : const Color(0xFF15803D),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Recenter Button (Dedicated, smart-target)
              AnimatedScale(
                scale: isPannedAway ? 1.0 : 0.92,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _MapControlButton(
                  key: const ValueKey('recenter_btn'),
                  tooltip: 'Recenter Map',
                  backgroundColor: isPannedAway ? const Color(0xFFEEF2FF) : Colors.white,
                  borderColor: isPannedAway ? const Color(0xFF818CF8) : Colors.black12,
                  onPressed: _handleRecenter,
                  child: Icon(
                    Icons.center_focus_strong_rounded,
                    color: isPannedAway ? const Color(0xFF4F46E5) : Colors.blueGrey.shade700,
                    size: 23,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 3. Current Location Button (Idle, Locating, Following, Error)
              _buildLocationButton(locationAsync, isPannedAway),
              const SizedBox(height: 12),

              // 4. Runtime Diagnostics Button
              _MapControlButton(
                key: const ValueKey('diag_btn'),
                tooltip: 'Developer Diagnostics',
                backgroundColor: Colors.white,
                borderColor: Colors.black12,
                onPressed: widget.onOpenDiagnostics,
                child: const Icon(
                  Icons.terminal_rounded,
                  color: Color(0xFF2563EB),
                  size: 21,
                ),
              ),
            ],
          ),
        ),

        // ── Emergency SOS Button (Bottom Left) ───────────────────────────────
        Positioned(
          bottom: widget.isAutoDetailsOpen ? 360 : 120,
          left: 20,
          child: _buildSosButton(),
        ),
      ],
    );
  }

  Widget _buildLocationButton(AsyncValue<Position?> locationAsync, bool isPannedAway) {
    final isLoading = locationAsync.isLoading;
    final hasError = locationAsync.hasError;
    final isFollowing = !isPannedAway && locationAsync.hasValue;

    Color bgColor = Colors.white;
    Color borderColor = Colors.black12;
    Color iconColor = const Color(0xFF1E293B);

    if (isLoading) {
      bgColor = const Color(0xFFEFF6FF);
      borderColor = const Color(0xFF93C5FD);
      iconColor = const Color(0xFF2563EB);
    } else if (hasError) {
      bgColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFCA5A5);
      iconColor = const Color(0xFFDC2626);
    } else if (isFollowing) {
      bgColor = const Color(0xFF2563EB);
      borderColor = const Color(0xFF1D4ED8);
      iconColor = Colors.white;
    }

    return _MapControlButton(
      key: const ValueKey('my_location_btn'),
      tooltip: hasError
          ? 'Location Error (Tap for help)'
          : (isFollowing ? 'Following Location' : 'Locate Me'),
      backgroundColor: bgColor,
      borderColor: borderColor,
      onPressed: _handleLocateMe,
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF2563EB)),
            )
          : Icon(
              hasError
                  ? Icons.location_off_rounded
                  : (isFollowing ? Icons.my_location_rounded : Icons.location_searching_rounded),
              color: iconColor,
              size: 23,
            ),
    );
  }

  Widget _buildSosButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTriggerSos,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emergency_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  'SOS',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable, elevated floating map control button with tactile feedback.
class _MapControlButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color backgroundColor;
  final Color borderColor;

  const _MapControlButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
    this.backgroundColor = Colors.white,
    this.borderColor = Colors.black12,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            splashColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
