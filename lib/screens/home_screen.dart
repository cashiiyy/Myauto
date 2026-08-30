import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../models/backend_event.dart';
import '../models/auto_model.dart';
import '../models/nearby_driver_model.dart';
import '../providers/auth_provider.dart';
import '../providers/backend_client_provider.dart';
import '../providers/backend_drivers_provider.dart';
import '../providers/destination_provider.dart';
import '../providers/location_provider.dart';
import '../providers/ride_action_provider.dart';
import '../providers/rtdb_provider.dart';
import '../providers/selected_driver_provider.dart';
import '../providers/user_provider.dart';
import '../providers/ws_event_router.dart';
import '../providers/ws_provider.dart';
import '../services/driver_location_service.dart';
import '../services/map/map_abstraction.dart';
import '../widgets/auto_details_sheet.dart';
import '../widgets/destination_search_bar.dart';
import 'activity_screen.dart';
import 'profile_screen.dart';
import 'profile_screen.dart';
import '../models/user_model.dart';
import '../services/routing/routing_service.dart';

// ── Map State ────────────────────────────────────────────────────────────────
final mapBoundsProvider = StateProvider<LatLngBounds?>((ref) => null);

final routeProvider = FutureProvider<RouteResult?>((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user?.role != 'passenger') return null;

  final posAsync = ref.watch(currentLocationProvider);
  final dest = ref.watch(destinationProvider);

  if (posAsync.value == null || dest == null) return null;

  final pos = LatLng(posAsync.value!.latitude, posAsync.value!.longitude);
  final destPos = LatLng(dest.latitude, dest.longitude);

  final routing = createRoutingService();
  return routing.getRoute(pos, destPos);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  int _currentIndex = 0;
  AutoModel? _selectedAuto;
  double _distanceToAuto = 0.0;

  // Driver service owned here — avoids Riverpod autoDispose race
  DriverLocationService? _driverService;

  @override
  void initState() {
    super.initState();
    // Boot the WS event router so it starts listening immediately
    ref.read(wsEventRouterProvider);
  }

  @override
  void dispose() {
    _driverService?.dispose();
    super.dispose();
  }

  // ── Driver service management ──────────────────────────────────────────────

  void _manageDriverService(UserModel? user) {
    if (user != null && user.role == 'driver') {
      if (_driverService == null) {
        final apiClient = ref.read(backendApiClientProvider);
        _driverService = DriverLocationService(apiClient, user);
        _driverService!.start();
      }
    } else {
      if (_driverService != null) {
        _driverService!.stop();
        _driverService!.dispose();
        _driverService = null;
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Select a backend-sourced NearbyDriverModel
  void _selectFromNearbyDriver(NearbyDriverModel d, dynamic position) {
    ref.read(selectedDriverProvider.notifier).state = d;
    final auto = AutoModel(
      id: d.driverUid,
      latitude: d.latitude,
      longitude: d.longitude,
      isAvailable: d.isAvailable,
      driverName: 'Auto Driver',    // Backend does not return name at discovery (privacy)
      phoneNumber: '',         // Phone number NEVER returned by nearby endpoint
      vehicleNumber: 'KL Auto',
      rating: d.rating ?? 5.0,
    );
    _selectAuto(auto, position);
  }

  void _selectAuto(AutoModel auto, dynamic currentPos) {
    if (currentPos != null) {
      _distanceToAuto = Geolocator.distanceBetween(
        currentPos.latitude, currentPos.longitude,
        auto.latitude, auto.longitude,
      ) / 1000.0;
    }
    setState(() => _selectedAuto = auto);
  }

  void _reloadMap() {
    ref.read(backendDriversProvider.notifier).refresh();
    final pos = ref.read(currentLocationProvider).value;
    if (pos != null) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
    }
  }

  void _callSos() async {
    final rideAction = ref.read(rideActionControllerProvider.notifier);
    // 1. Notify backend
    await rideAction.triggerSos();
    // 2. Always open phone dialer (safety first)
    final sosNumber = ref.read(sosContactProvider);
    final url = Uri(scheme: 'tel', path: sosNumber);
    if (await canLaunchUrl(url)) launchUrl(url);
  }

  void _toggleRole(UserModel? user) async {
    // Guard: profile must be loaded before a role toggle is meaningful.
    if (user == null) return;

    final newRole = user.role.toLowerCase() == 'driver' ? 'passenger' : 'driver';

    final updatedUser = user.copyWith(role: newRole);
    await ref.read(authControllerProvider.notifier).createUserDocument(updatedUser);
    ref.read(localSessionProvider.notifier).state = updatedUser;
    ref.invalidate(currentUserProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${newRole == 'driver' ? "Driver" : "Passenger"} Mode!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Driver Accept/Reject Sheet ─────────────────────────────────────────────

  void _showRideRequestSheet(BackendEvent event) {
    final pickupLat = (event.payload['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (event.payload['pickup_lng'] as num?)?.toDouble();
    final destinationLat = (event.payload['destination_lat'] as num?)?.toDouble();
    final destinationLng = (event.payload['destination_lng'] as num?)?.toDouble();
    final destinationLabel = event.payload['destination_label'] as String?;
    final passengerName = event.payload['passenger_name'] as String? ?? 'Passenger';
    final approxDistanceKm = (event.payload['approx_distance_km'] as num?)?.toDouble();
    final estimatedDurationMin = (event.payload['estimated_duration_min'] as num?)?.toInt();
    final expiresAtStr = event.payload['expires_at'] as String?;
    final matchId = event.payload['match_id'] as String? ?? event.rideId ?? '';
    final notes = event.payload['notes'] as String?;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RideRequestSheet(
        matchId: matchId,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        destinationLabel: destinationLabel,
        passengerName: passengerName,
        approxDistanceKm: approxDistanceKm,
        estimatedDurationMin: estimatedDurationMin,
        expiresAt: expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null,
        notes: notes,
        onAccept: () async {
          final ctrl = ref.read(rideActionControllerProvider.notifier);
          await ctrl.acceptMatch(matchId);
          if (mounted) Navigator.of(ctx).pop();
          ref.read(incomingRideRequestProvider.notifier).state = null;
        },
        onReject: () async {
          final ctrl = ref.read(rideActionControllerProvider.notifier);
          await ctrl.rejectMatch(matchId);
          if (mounted) Navigator.of(ctx).pop();
          ref.read(incomingRideRequestProvider.notifier).state = null;
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Sync driver service with current user state (idempotent)
    final user = ref.watch(currentUserProvider).value;
    _manageDriverService(user);

    // Watch for incoming ride requests (driver-side) and show sheet
    ref.listen<BackendEvent?>(incomingRideRequestProvider, (prev, next) {
      if (next != null && prev?.eventId != next.eventId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRideRequestSheet(next);
        });
      }
    });

    // Watch for route bounds updates and adjust camera
    ref.listen<LatLngBounds?>(mapBoundsProvider, (prev, next) {
      if (next != null && mounted) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: next,
            padding: const EdgeInsets.all(50.0),
          ),
        );
      }
    });

    ref.listen<AsyncValue<RouteResult?>>(routeProvider, (prev, next) {
      final route = next.value;
      if (route != null && mounted) {
        final posAsync = ref.read(currentLocationProvider);
        final dest = ref.read(destinationProvider);
        if (posAsync.value != null && dest != null) {
          final pos = LatLng(posAsync.value!.latitude, posAsync.value!.longitude);
          final destPos = LatLng(dest.latitude, dest.longitude);
          final bounds = LatLngBounds.fromPoints([pos, destPos, ...route.polyline]);
          ref.read(mapBoundsProvider.notifier).state = bounds;
        }
      }
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [_buildMapTab(), const ActivityScreen(), const ProfileScreen()],
          ),
          // ── Connection status banner ────────────────────────────────────
          if (_currentIndex == 0) _buildConnectionBanner(),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            bottom: _selectedAuto == null ? 30 : -100,
            left: 20, right: 20,
            child: _buildCustomBottomBar(),
          ),
        ],
      ),
    );
  }

  // ── Connection status banner (3px bar at top of map) ──────────────────────

  Widget _buildConnectionBanner() {
    final wsState = ref.watch(wsConnectionStateProvider);
    return wsState.when(
      loading: () => const SizedBox(),
      error: (_, __) => _connectionBar(Colors.red),
      data: (state) {
        if (AppConfig.mockMode) return const SizedBox();
        return switch (state) {
          WsConnectionState.connected => const SizedBox(), // Green = no banner
          WsConnectionState.connecting => _connectionBar(Colors.amber.shade600, label: 'Connecting…'),
          WsConnectionState.reconnecting => _connectionBar(Colors.orange, label: 'Reconnecting…'),
          WsConnectionState.disconnected => _connectionBar(Colors.red.shade400, label: 'Offline'),
          WsConnectionState.authFailed => _connectionBar(Colors.red.shade700, label: 'Auth failed'),
          WsConnectionState.error => _connectionBar(Colors.red, label: 'Connection error'),
        };
      },
    );
  }

  void _showDiagnosticsSheet(String role) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DiagnosticsSheet(
        role: role,
        driverService: _driverService,
      ),
    );
  }

  Widget _connectionBar(Color color, {String? label}) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 4,
      left: 48,
      right: 48,
      child: GestureDetector(
        onTap: () {
          final user = ref.read(currentUserProvider).value;
          _showDiagnosticsSheet(user?.role ?? 'passenger');
        },
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 400),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)],
            ),
            child: label != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 10, height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Text(label,
                          style: GoogleFonts.inter(
                              fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  )
                : const SizedBox(height: 3),
          ),
        ),
      ),
    );
  }

  // ── Map tab ────────────────────────────────────────────────────────────────

  Widget _buildMapTab() {
    final locationAsync = ref.watch(currentLocationProvider);
    final currentUserAsync = ref.watch(currentUserProvider);
    final currentUser = currentUserAsync.value;

    // While the authenticated profile has not yet arrived from Firestore,
    // show a neutral loading state. This prevents stale in-memory state
    // (e.g. a previous driver session) from incorrectly gating passenger UI.
    if (currentUserAsync.isLoading && currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Single authoritative role source: authenticated Firestore UserModel.
    // Falls back to 'passenger' only when Firestore confirms no document
    // exists — auth_provider.dart already creates a fallback doc with role='passenger'.
    final role = (currentUser?.role ?? 'passenger').toLowerCase();

    // ── Backend driver state (primary) ─────────────────────────────────────
    final backendDriversState = ref.watch(backendDriversProvider);

    // ── RTDB ride shares (still active for co-passenger feature) ───────────
    final sharesAsync = ref.watch(nearbyRideSharesStreamProvider);

    final pos = locationAsync.value;
    // Default to a fallback location if GPS is not yet available, so map renders.
    final userLoc = pos != null ? LatLng(pos.latitude, pos.longitude) : const LatLng(8.5241, 76.9366); 

    // Read destination for the pin marker (passenger-only, additive)
    final destination = ref.watch(destinationProvider);

    return Stack(
      children: [
        // ── Map always renders ──────────────────────────────────────────
        GestureDetector(
          onTap: () { if (_selectedAuto != null) setState(() => _selectedAuto = null); },
          child: MapAbstraction(
            mapController: _mapController,
            initialCenter: userLoc,
            initialZoom: 15.0,
            onTap: (_, __) => setState(() => _selectedAuto = null),
            children: [
              if (AppConfig.cartoBasemapApiKey.isEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black87,
                    child: const Text(
                      'CARTO API KEY REQUIRED',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                TileLayer(
                  urlTemplate: AppConfig.tileUrl,
                  userAgentPackageName: 'com.myauto.com',
                ),

              // ── Route Polyline (Passenger) ───────────────────────
              ...ref.watch(routeProvider).when(
                data: (route) {
                  if (route == null) return [];
                  return [
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route.polyline,
                          strokeWidth: 4.0,
                          color: Colors.blue,
                        ),
                      ],
                    )
                  ];
                },
                loading: () => [],
                error: (_, __) => [],
              ),

              MarkerLayer(markers: [
                // ── Own position marker ──────────────────────────────
                if (pos != null)
                  Marker(
                    point: userLoc, width: 40, height: 40,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                  ),

                // ── Passenger sees nearby DRIVERS from backend (🛺) ──
                if (role == 'passenger')
                  ...backendDriversState.drivers.map((d) {
                    if (d.isStale) return null; // filter stale
                    final isSelected = _selectedAuto?.id == d.driverUid;
                    return Marker(
                      point: LatLng(d.latitude, d.longitude),
                      width: isSelected ? 60 : 50,
                      height: isSelected ? 60 : 50,
                      child: GestureDetector(
                        onTap: () => _selectFromNearbyDriver(d, pos),
                            child: Stack(alignment: Alignment.center, children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: d.isAvailable
                                      ? Colors.green.withValues(alpha: 0.5)
                                      : Colors.red.withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(color: Colors.black, width: 2)
                                      : null,
                                ),
                                width: isSelected ? 50 : 40,
                                height: isSelected ? 50 : 40,
                              ),
                              Text('🛺',
                                  style: TextStyle(fontSize: isSelected ? 30 : 24)),
                            ]),
                          ),
                        );
                      }).whereType<Marker>().toList(),

                    // ── Driver sees a pulse marker when a ride.requested event arrives
                    // (the accept/reject sheet handles the actual interaction)
                    if (role == 'driver') ..._buildIncomingRequestPulse(),

                    // ── Co-passengers sharing ride (🤝) — RTDB source ────
                    ...sharesAsync.when(
                      loading: () => <Marker>[],
                      error: (e, _) {
                        debugPrint('🔴 [Shares] $e');
                        return <Marker>[];
                      },
                      data: (shares) => shares.map((s) => Marker(
                        point: LatLng(s.latitude, s.longitude),
                        width: 48, height: 48,
                        child: Tooltip(
                          message: '${s.name} — share ride',
                          child: Stack(alignment: Alignment.center, children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              width: 40, height: 40,
                            ),
                            const Text('🤝', style: TextStyle(fontSize: 22)),
                          ]),
                        ),
                      )).toList(),
                    ),

                    // ── Destination pin marker (passenger-only, additive) ──
                    // Appears when passenger selects a destination from search.
                    // Does NOT trigger any booking or matching logic.
                    if (role == 'passenger' && destination != null)
                      Marker(
                        point: LatLng(destination.latitude, destination.longitude),
                        width: 48,
                        height: 48,
                        child: Tooltip(
                          message: destination.displayLabel,
                          child: Stack(alignment: Alignment.topCenter, children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF007AFF),
                                  width: 2,
                                ),
                              ),
                              width: 38,
                              height: 38,
                            ),
                            const Positioned(
                              top: 4,
                              child: Text('📍', style: TextStyle(fontSize: 22)),
                            ),
                          ]),
                        ),
                      ),
                  ]),
                ],
              ),
            ),

        // ── Location loading overlay ──────────────────────────────────────
        if (locationAsync.isLoading && pos == null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Acquiring GPS location...'),
                ],
              ),
            ),
          ),
        if (locationAsync.hasError)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              child: Text('Location error: ${locationAsync.error}'),
            ),
          ),

        // ── FABs ──────────────────────────────────────────────────────────
        if (_currentIndex == 0) ...[

          // ── Destination search bar (passengers only — additive) ─────────
          // Positioned at top of map, above connection banner, below FABs.
          // Hidden for drivers. Does not affect booking or ride logic.
          if (role == 'passenger') ...[
            Builder(builder: (ctx) {
              debugPrint('[Diagnostics] home_screen adding DestinationSearchBar to Stack. padding.top: ${MediaQuery.of(ctx).padding.top}');
              return Positioned(
                top: MediaQuery.of(ctx).padding.top + 10,
                left: 0, right: 0,
                child: const DestinationSearchBar(),
              );
            }),
          ] else ...[
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              child: InkWell(
                onTap: () => _toggleRole(currentUser),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(color: const Color(0xFFFF9500), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🚖', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        'Driver Mode (Tap to Switch)',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFF9500),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.swap_horiz, size: 16, color: Color(0xFFFF9500)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          // Backend poll error indicator
          if (ref.watch(backendDriversProvider).error != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              left: 60, right: 60,
              child: const SizedBox(), // banner handles this
            ),

          Positioned(
            // Shift down for passengers (search bar occupies ~62px at top)
            top: MediaQuery.of(context).padding.top + (role == 'passenger' ? 72 : 20),
            right: 20,
            child: FloatingActionButton(
              heroTag: 'refresh',
              backgroundColor: const Color(0xFFFFDDBA).withValues(alpha: 0.9),
              elevation: 4, mini: true,
              onPressed: _reloadMap,
              child: const Icon(Icons.refresh, color: Colors.black87),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + (role == 'passenger' ? 122 : 70),
            right: 20,
            child: FloatingActionButton(
              heroTag: 'locate',
              backgroundColor: const Color(0xFFD0E4FF).withValues(alpha: 0.9),
              elevation: 4, mini: true,
              onPressed: () {
                final pos = ref.read(currentLocationProvider).value;
                if (pos != null) {
                  _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
                }
              },
              child: const Icon(Icons.my_location, color: Colors.black87),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + (role == 'passenger' ? 172 : 120),
            right: 20,
            child: FloatingActionButton(
              heroTag: 'diag',
              backgroundColor: Colors.white.withValues(alpha: 0.95),
              elevation: 4, mini: true,
              onPressed: () => _showDiagnosticsSheet(role),
              child: const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 20),
            ),
          ),
          Positioned(
            bottom: _selectedAuto == null ? 120 : 350, left: 20,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: FloatingActionButton(
                heroTag: 'sos',
                backgroundColor: const Color(0xFFFF4B4B),
                elevation: 4, shape: const CircleBorder(),
                onPressed: _callSos,
                child: const Icon(Icons.call, color: Colors.white, size: 28),
              ),
            ),
          ),

          // ── Book Ride + Share Ride (passengers) ───────────────────────
          if (role == 'passenger')
            Positioned(
              bottom: _selectedAuto == null ? 120 : 360, right: 20,
              child: _buildPassengerActionBar(ref.watch(rideActionControllerProvider)),
            ),

          // ── Details sheet ─────────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            bottom: _selectedAuto == null ? -400 : 0,
            left: 0, right: 0, height: 350,
            child: _selectedAuto != null
                ? AutoDetailsSheet(
                    auto: _selectedAuto!,
                    distance: _distanceToAuto,
                    onClose: () => setState(() => _selectedAuto = null),
                  )
                : const SizedBox(),
          ),
        ],
      ],
    );
  }

  /// When a ride.requested event arrives, show a pulsing passenger marker
  /// at the pickup location.
  List<Marker> _buildIncomingRequestPulse() {
    final event = ref.watch(incomingRideRequestProvider);
    if (event == null) return [];
    final lat = (event.payload['pickup_lat'] as num?)?.toDouble();
    final lng = (event.payload['pickup_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return [];
    return [
      Marker(
        point: LatLng(lat, lng),
        width: 56, height: 56,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1.2),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          builder: (_, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue.shade800, width: 2),
            ),
            child: const Center(child: Text('🧍', style: TextStyle(fontSize: 26))),
          ),
        ),
      ),
    ];
  }

  // ── Passenger action bar ───────────────────────────────────────────────────

  Widget _buildPassengerActionBar(RideActionState rideAction) {
    final isLoading = rideAction.status == RideActionStatus.loading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'share_ride',
          tooltip: rideAction.isSharing ? 'Disable Share' : 'Enable Share',
          backgroundColor: rideAction.isSharing
              ? Colors.teal
              : Colors.white.withValues(alpha: 0.9),
          onPressed: isLoading ? null : () async {
            final ctrl = ref.read(rideActionControllerProvider.notifier);
            rideAction.isSharing
                ? await ctrl.disableRideShare()
                : await ctrl.enableRideShare();
          },
          child: Text('🤝', style: TextStyle(fontSize: rideAction.isSharing ? 18 : 16)),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'book_ride',
          backgroundColor:
              rideAction.isRequesting ? Colors.red.shade400 : const Color(0xFF007AFF),
          elevation: 4,
          onPressed: isLoading ? null : () async {
            final ctrl = ref.read(rideActionControllerProvider.notifier);
            rideAction.isRequesting ? await ctrl.cancelRide() : await ctrl.bookRide();
          },
          icon: isLoading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(rideAction.isRequesting ? Icons.close : Icons.hail, color: Colors.white),
          label: Text(
            rideAction.isRequesting ? 'Cancel' : 'Book Ride',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ── Bottom navigation bar ──────────────────────────────────────────────────

  Widget _buildCustomBottomBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabItem(0, 'Map', Icons.place),
              _buildTabItem(1, 'Activity', Icons.notes),
              _buildTabItem(2, 'Profile', Icons.person),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label, IconData icon) {
    final isSelected = _currentIndex == index;
    const activeColor = Color(0xFF007AFF);
    return GestureDetector(
      onTap: () => setState(() {
        _currentIndex = index;
        if (index != 0) _selectedAuto = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (Theme.of(context).brightness == Brightness.dark
                  ? activeColor.withValues(alpha: 0.2)
                  : activeColor.withValues(alpha: 0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
              color: isSelected ? activeColor
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54 : Colors.grey[600]),
              size: 20),
            if (isSelected)
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.bold, color: activeColor)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Driver Accept/Reject Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

// Driver Accept/Reject Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RideRequestSheet extends StatefulWidget {
  final String matchId;
  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final String? destinationLabel;
  final String passengerName;
  final double? approxDistanceKm;
  final int? estimatedDurationMin;
  final DateTime? expiresAt;
  final String? notes;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RideRequestSheet({
    required this.matchId,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.destinationLabel,
    required this.passengerName,
    this.approxDistanceKm,
    this.estimatedDurationMin,
    this.expiresAt,
    this.notes,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_RideRequestSheet> createState() => _RideRequestSheetState();
}

class _RideRequestSheetState extends State<_RideRequestSheet> {
  int _secondsRemaining = 30;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.expiresAt != null) {
      final diff = widget.expiresAt!.difference(DateTime.now()).inSeconds;
      _secondsRemaining = diff > 0 ? diff : 0;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 1) {
        setState(() => _secondsRemaining--);
      } else {
        setState(() => _secondsRemaining = 0);
        timer.cancel();
        widget.onReject();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = widget.pickupLat != null && widget.pickupLng != null;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, -4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header + Countdown Chip
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(child: Text('🧍', style: TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.passengerName,
                            style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                        const SizedBox(height: 2),
                        Text('Requested a ride',
                            style: GoogleFonts.inter(
                                fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  // Expiry countdown chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _secondsRemaining <= 10 ? Colors.red.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _secondsRemaining <= 10 ? Colors.red.shade200 : Colors.amber.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 14,
                            color: _secondsRemaining <= 10 ? Colors.red.shade700 : Colors.amber.shade800),
                        const SizedBox(width: 4),
                        Text('${_secondsRemaining}s',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _secondsRemaining <= 10 ? Colors.red.shade700 : Colors.amber.shade900,
                            )),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Trip details card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    if (hasCoords)
                      _InfoRow(
                        icon: Icons.my_location,
                        iconColor: Colors.blue,
                        label: 'Pickup',
                        value: '${widget.pickupLat!.toStringAsFixed(5)}, ${widget.pickupLng!.toStringAsFixed(5)}',
                      ),
                    if (widget.destinationLabel != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1),
                      ),
                      _InfoRow(
                        icon: Icons.flag,
                        iconColor: Colors.deepOrange,
                        label: 'Destination',
                        value: widget.destinationLabel!,
                      ),
                    ],
                    if (widget.approxDistanceKm != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1),
                      ),
                      _InfoRow(
                        icon: Icons.route_outlined,
                        iconColor: Colors.purple,
                        label: 'Estimated Trip',
                        value: '${widget.approxDistanceKm} km (${widget.estimatedDurationMin ?? 5} mins)',
                      ),
                    ],
                  ],
                ),
              ),

              if (widget.notes != null && widget.notes!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.notes_outlined,
                  label: 'Passenger Note',
                  value: widget.notes!,
                ),
              ],

              const SizedBox(height: 20),

              // Accept / Reject buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onReject,
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: Text('Decline',
                          style: GoogleFonts.inter(
                              color: Colors.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: widget.onAccept,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: Text('Accept Ride',
                          style: GoogleFonts.inter(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF34C759),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor ?? Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500),
                ),
                TextSpan(
                  text: value,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Real-Time System Diagnostics Modal Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DiagnosticsSheet extends ConsumerStatefulWidget {
  final String role;
  final DriverLocationService? driverService;

  const _DiagnosticsSheet({
    required this.role,
    this.driverService,
  });

  @override
  ConsumerState<_DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends ConsumerState<_DiagnosticsSheet> {
  String? _healthStatus;
  bool _pinging = false;

  Future<void> _pingHealth() async {
    setState(() {
      _pinging = true;
      _healthStatus = 'Pinging...';
    });
    final stopwatch = Stopwatch()..start();
    try {
      final ok = await ref.read(backendApiClientProvider).checkHealth();
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _pinging = false;
          _healthStatus = ok
              ? '✅ 200 OK (${stopwatch.elapsedMilliseconds}ms)'
              : '❌ Unhealthy (${stopwatch.elapsedMilliseconds}ms)';
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _pinging = false;
          _healthStatus = '❌ Failed: $e';
        });
      }
    }
  }

  void _copyToClipboard(BuildContext context, Map<String, dynamic> data) {
    Clipboard.setData(ClipboardData(text: data.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? 'Not authenticated';
    final location = ref.watch(currentLocationProvider).value;
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull ?? WsConnectionState.disconnected;
    final rideAction = ref.watch(rideActionControllerProvider);
    final incomingRequest = ref.watch(incomingRideRequestProvider);
    final nearbyDrivers = ref.watch(backendDriversProvider).drivers;
    final wsClient = ref.watch(wsClientProvider);

    final isDevUrl = AppConfig.backendUrl.contains('localhost') ||
        AppConfig.backendUrl.contains('127.0.0.1') ||
        AppConfig.backendUrl.contains('10.0.2.2') ||
        AppConfig.backendUrl.contains('192.168.');

    final summary = {
      'role': widget.role,
      'uid': authUid,
      'rest_url': AppConfig.backendUrl,
      'ws_url': AppConfig.backendWsUrl,
      'ws_state': wsState.name,
      'lat': location?.latitude,
      'lng': location?.longitude,
      'accuracy_m': location?.accuracy,
      'ride_status': rideAction.status.name,
      'backend_request_id': rideAction.backendRequestId,
      'matched_driver_uid': rideAction.matchedDriverUid,
      'incoming_request_id': incomingRequest?.rideId,
      'nearby_drivers_count': nearbyDrivers.length,
    };

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header handle & title
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'System Diagnostics',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: 'Copy JSON Summary',
                          onPressed: () => _copyToClipboard(context, summary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Card 0: Build Identity ──────────────────────────────────
                _diagCard(
                  title: 'Build Identity',
                  icon: Icons.build_circle_outlined,
                  children: [
                    _diagRow('Build Timestamp', AppConfig.buildTimestamp),
                    _diagRow('Git Commit', AppConfig.gitCommit),
                    _diagRow('Realtime Mode', AppConfig.realtimeMode),
                    _diagRow('CARTO Key', AppConfig.cartoBasemapApiKey.isNotEmpty ? 'Present ✅' : 'Missing ❌', 
                        color: AppConfig.cartoBasemapApiKey.isNotEmpty ? Colors.green.shade700 : Colors.red),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Card 1: Identity & Role ──────────────────────────────────
                _diagCard(
                  title: 'Device Identity & Role',
                  icon: Icons.person_outline,
                  children: [
                    _diagRow('Authoritative Role', widget.role.toUpperCase(),
                        highlight: true,
                        color: widget.role == 'driver' ? Colors.orange.shade700 : Colors.blue.shade700),
                    _diagRow('Firebase UID', authUid),
                    _diagRow('Display Name', user?.name ?? 'None'),
                    _diagRow('Phone', user?.phone ?? 'None'),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Card 2: Endpoints & Connectivity ─────────────────────────
                _diagCard(
                  title: 'Backend Endpoints & Transport',
                  icon: Icons.cloud_outlined,
                  children: [
                    _diagRow('REST URL', AppConfig.backendUrl),
                    _diagRow('WebSocket URL', AppConfig.backendWsUrl),
                    _diagRow('Target Environment', isDevUrl ? '⚠️ LOCAL/DEV' : '🌐 PUBLIC MULTI-NETWORK',
                        color: isDevUrl ? Colors.orange : Colors.green.shade700),
                    _diagRow('WebSocket State', wsState.name.toUpperCase(),
                        color: wsState == WsConnectionState.connected ? Colors.green.shade700 : Colors.red),
                    if (wsClient.connectedAt != null)
                      _diagRow('Connected Since', wsClient.connectedAt!.toLocal().toString().split('.').first),
                    if (wsClient.lastMessageAt != null)
                      _diagRow('Last Msg Received', wsClient.lastMessageAt!.toLocal().toString().split('.').first),
                    _diagRow('Reconnect Attempts', '${wsClient.reconnectCount}'),
                    if (wsClient.lastError != null)
                      _diagRow('Last WS Error', wsClient.lastError!, color: Colors.red),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pinging ? null : _pingHealth,
                          icon: _pinging
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.network_ping, size: 16),
                          label: const Text('Ping /health'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_healthStatus != null)
                          Expanded(
                            child: Text(
                              _healthStatus!,
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Card 3: GPS & Pipeline ───────────────────────────────────
                _diagCard(
                  title: 'Live GPS & Location Pipeline',
                  icon: Icons.gps_fixed,
                  children: [
                    _diagRow('Latitude', location?.latitude.toStringAsFixed(6) ?? 'None'),
                    _diagRow('Longitude', location?.longitude.toStringAsFixed(6) ?? 'None'),
                    _diagRow('Accuracy', '${location?.accuracy.toStringAsFixed(1) ?? 'None'} m'),
                    _diagRow('Speed', '${location?.speed.toStringAsFixed(1) ?? 'None'} m/s'),
                    _diagRow('Heading', '${location?.heading.toStringAsFixed(1) ?? 'None'}°'),
                    if (widget.role == 'driver') ...[
                      const Divider(),
                      _diagRow('Driver Publisher', widget.driverService?.isRunning == true ? 'Active 🟢' : 'Stopped 🔴'),
                      _diagRow('GPS Sequence', '${widget.driverService?.sequence ?? 0}'),
                      _diagRow('Last Send Status', widget.driverService?.lastSendStatus ?? 'None'),
                      _diagRow('Last Sent Time', widget.driverService?.lastSentTime?.toLocal().toString().split('.').first ?? 'None'),
                    ] else ...[
                      const Divider(),
                      _diagRow('Nearby Drivers Count', '${nearbyDrivers.length}'),
                      if (nearbyDrivers.isNotEmpty)
                        ...nearbyDrivers.map((d) => _diagRow(
                              '🛺 Driver ${d.driverUid.substring(0, math.min(6, d.driverUid.length))}',
                              '${d.distanceKm.toStringAsFixed(2)}km | ${d.isAvailable ? "AVAILABLE" : "BUSY"} | ${d.freshness}',
                            )),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // ── Card 4: Ride Request State ──────────────────────────────
                _diagCard(
                  title: 'Ride State & Matches',
                  icon: Icons.local_taxi_outlined,
                  children: [
                    _diagRow('Ride Action Status', rideAction.status.name.toUpperCase()),
                    _diagRow('Backend Request ID', rideAction.backendRequestId ?? 'None'),
                    _diagRow('Matched Driver UID', rideAction.matchedDriverUid ?? 'None'),
                    _diagRow('Target Driver UID', rideAction.selectedDriverUid ?? 'None'),
                    _diagRow('Match ID', rideAction.matchId ?? 'None'),
                    _diagRow('Message', rideAction.message ?? 'None'),
                    if (incomingRequest != null) ...[
                      const Divider(),
                      _diagRow('Incoming Ride ID', incomingRequest.rideId ?? 'None', color: Colors.blue.shade700),
                      _diagRow('Passenger Name', incomingRequest.payload['passenger_name']?.toString() ?? 'None'),
                      _diagRow('Expires At', incomingRequest.payload['expires_at']?.toString() ?? 'None'),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diagCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _diagRow(String label, String value, {bool highlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: color ?? (highlight ? Colors.blue.shade800 : Colors.black87),
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

