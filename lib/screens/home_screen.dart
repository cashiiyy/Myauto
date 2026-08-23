import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../models/backend_event.dart';
import '../models/auto_model.dart';
import '../models/nearby_driver_model.dart';
import '../providers/auth_provider.dart';
import '../providers/backend_client_provider.dart';
import '../providers/backend_drivers_provider.dart';
import '../providers/location_provider.dart';
import '../providers/ride_action_provider.dart';
import '../providers/rtdb_provider.dart';
import '../providers/user_provider.dart';
import '../providers/ws_event_router.dart';
import '../providers/ws_provider.dart';
import '../services/driver_location_service.dart';
import '../widgets/auto_details_sheet.dart';
import 'activity_screen.dart';
import 'profile_screen.dart';
import '../models/user_model.dart';

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
    final auto = AutoModel(
      id: d.driverUid,
      latitude: d.latitude,
      longitude: d.longitude,
      isAvailable: d.isAvailable,
      driverName: 'Driver',    // Backend does not return name (privacy)
      phoneNumber: '',         // Phone number NEVER returned by nearby endpoint
      vehicleNumber: '',
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

  // ── Driver Accept/Reject Sheet ─────────────────────────────────────────────

  void _showRideRequestSheet(BackendEvent event) {
    final pickupLat = (event.payload['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (event.payload['pickup_lng'] as num?)?.toDouble();
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

  Widget _connectionBar(Color color, {String? label}) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 4,
      left: 48,
      right: 48,
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
    );
  }

  // ── Map tab ────────────────────────────────────────────────────────────────

  Widget _buildMapTab() {
    final locationAsync = ref.watch(currentLocationProvider);
    final role = ref.watch(currentUserProvider).value?.role ?? 'passenger';
    final rideAction = ref.watch(rideActionControllerProvider);

    // ── Backend driver state (primary) ─────────────────────────────────────
    final backendDriversState = ref.watch(backendDriversProvider);

    // ── RTDB ride shares (still active for co-passenger feature) ───────────
    final sharesAsync = ref.watch(nearbyRideSharesStreamProvider);

    return Stack(
      children: [
        locationAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Location error: $e')),
          data: (position) {
            if (position == null) {
              return const Center(child: Text('Location unavailable. Check permissions.'));
            }
            final userLoc = LatLng(position.latitude, position.longitude);

            return GestureDetector(
              onTap: () { if (_selectedAuto != null) setState(() => _selectedAuto = null); },
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: userLoc,
                  initialZoom: 15.0,
                  onTap: (_, __) => setState(() => _selectedAuto = null),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.myauto.com',
                  ),
                  MarkerLayer(markers: [
                    // ── Own position marker ──────────────────────────────
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
                            onTap: () => _selectFromNearbyDriver(d, position),
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
                  ]),
                ],
              ),
            );
          },
        ),

        // ── FABs ──────────────────────────────────────────────────────────
        if (_currentIndex == 0) ...[
          // Backend poll error indicator
          if (ref.watch(backendDriversProvider).error != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              left: 60, right: 60,
              child: const SizedBox(), // banner handles this
            ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 20, right: 20,
            child: FloatingActionButton(
              heroTag: 'refresh',
              backgroundColor: const Color(0xFFFFDDBA).withValues(alpha: 0.9),
              elevation: 4, mini: true,
              onPressed: _reloadMap,
              child: const Icon(Icons.refresh, color: Colors.black87),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 70, right: 20,
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
          if ((ref.watch(currentUserProvider).value?.role ?? 'passenger') == 'passenger')
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

class _RideRequestSheet extends StatelessWidget {
  final String matchId;
  final double? pickupLat;
  final double? pickupLng;
  final String? notes;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RideRequestSheet({
    required this.matchId,
    this.pickupLat,
    this.pickupLng,
    this.notes,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final hasCoords = pickupLat != null && pickupLng != null;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
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
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
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
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Incoming Ride Request',
                            style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text('A passenger needs a ride',
                            style: GoogleFonts.inter(
                                fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Pickup info
              if (hasCoords)
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Pickup',
                  value:
                      '${pickupLat!.toStringAsFixed(5)}, ${pickupLng!.toStringAsFixed(5)}',
                ),
              if (notes != null && notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.notes_outlined,
                  label: 'Note',
                  value: notes!,
                ),
              ],

              const SizedBox(height: 24),

              // Accept / Reject buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
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
                      onPressed: onAccept,
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
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
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
