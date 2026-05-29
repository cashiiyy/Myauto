import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/location_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/rtdb_provider.dart';
import '../providers/ride_action_provider.dart';
import '../models/auto_model.dart';
import '../widgets/auto_details_sheet.dart';
import 'activity_screen.dart';
import 'profile_screen.dart';
import '../providers/user_provider.dart';
import 'package:google_fonts/google_fonts.dart';

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

  // ── Driver service lifecycle ───────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Defer so we can safely call ref after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDriverService());
  }

  /// If the logged-in user is a driver, kick off the GPS push loop.
  void _startDriverService() {
    final user = ref.read(currentUserProvider).value;
    if (user?.role == 'driver') {
      try {
        ref
            .read(driverLocationServiceProvider.notifier)
            .start()
            .catchError((e) => debugPrint('[HomeScreen] Driver service error: $e'));
      } catch (_) {
        // Provider throws if RTDB is unavailable — silently degrade.
      }
    }
  }

  @override
  void dispose() {
    // The autoDispose provider handles timer teardown automatically.
    super.dispose();
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  void _selectAuto(AutoModel auto, Position? currentPos) {
    if (currentPos != null) {
      _distanceToAuto = Geolocator.distanceBetween(
        currentPos.latitude, currentPos.longitude,
        auto.latitude, auto.longitude,
      ) / 1000.0;
    }
    setState(() => _selectedAuto = auto);
  }

  void _callSos() async {
    final sosNumber = ref.read(sosContactProvider);
    final Uri url = Uri(scheme: 'tel', path: sosNumber);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _reloadMap() {
    final pos = ref.read(currentLocationProvider).value;
    if (pos != null) {
      _mapController.move(
          LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
    }
  }

  // ── Main build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              _buildMapTab(),
              const ActivityScreen(),
              const ProfileScreen(),
            ],
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            bottom: _selectedAuto == null ? 30 : -100,
            left: 20,
            right: 20,
            child: _buildCustomBottomBar(),
          ),
        ],
      ),
    );
  }

  // ── Map tab ────────────────────────────────────────────────────────────────

  Widget _buildMapTab() {
    final locationAsync = ref.watch(currentLocationProvider);
    final userAsync = ref.watch(currentUserProvider);

    final role = userAsync.value?.role ?? 'passenger';

    // ── Choose the right RTDB stream based on role ──────────────────
    // Passengers → see nearby active drivers from RTDB.
    // Drivers    → see nearby ride requests from RTDB.
    final mapMarkersAsync = role == 'passenger'
        ? ref.watch(rtdbAutoListStreamProvider)
        : ref.watch(rtdbPassengerListStreamProvider);

    // Ride-share co-passengers (shown for everyone)
    final rideSharesAsync = ref.watch(nearbyRideSharesStreamProvider);

    final rideAction = ref.watch(rideActionControllerProvider);

    return Stack(
      children: [
        locationAsync.when(
          data: (position) {
            if (position == null) {
              return const Center(child: Text('Location Denied.'));
            }
            final userLocation = LatLng(position.latitude, position.longitude);

            return GestureDetector(
              onTap: () {
                if (_selectedAuto != null) {
                  setState(() => _selectedAuto = null);
                }
              },
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: userLocation,
                  initialZoom: 15.0,
                  onTap: (tapPosition, point) {
                    setState(() => _selectedAuto = null);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.my_auto',
                  ),
                  MarkerLayer(
                    markers: [
                      // ── User's own position ────────────────────────────
                      Marker(
                        point: userLocation,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.my_location,
                            color: Colors.blue, size: 30),
                      ),

                      // ── Nearby drivers (passenger view) or
                      //    ride requests (driver view) from RTDB ──────────
                      ...mapMarkersAsync.when(
                        data: (targetList) => targetList.map((target) {
                          final isSelected = _selectedAuto?.id == target.id;
                          return Marker(
                            point: LatLng(target.latitude, target.longitude),
                            width: isSelected ? 60 : 50,
                            height: isSelected ? 60 : 50,
                            child: GestureDetector(
                              onTap: () => _selectAuto(target, position),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: target.isAvailable
                                          ? Colors.green.withValues(alpha: 0.5)
                                          : Colors.red.withValues(alpha: 0.4),
                                      shape: BoxShape.circle,
                                      border: isSelected
                                          ? Border.all(
                                              color: Colors.black, width: 2)
                                          : null,
                                    ),
                                    width: isSelected ? 50 : 40,
                                    height: isSelected ? 50 : 40,
                                  ),
                                  Text(
                                    role == 'passenger' ? '🛺' : '🧍',
                                    style: TextStyle(
                                        fontSize: isSelected ? 30 : 24),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        loading: () => [],
                        error: (_, __) => [],
                      ),

                      // ── Ride-share co-passengers (green 🤝 markers) ──────
                      ...rideSharesAsync.when(
                        data: (shares) => shares.map((share) => Marker(
                              point: LatLng(share.latitude, share.longitude),
                              width: 48,
                              height: 48,
                              child: Tooltip(
                                message: '${share.name} — share available',
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.teal.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      width: 40,
                                      height: 40,
                                    ),
                                    const Text('🤝',
                                        style: TextStyle(fontSize: 22)),
                                  ],
                                ),
                              ),
                            )).toList(),
                        loading: () => [],
                        error: (_, __) => [],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        ),

        // ── FABs and overlays ──────────────────────────────────────────────
        if (_currentIndex == 0) ...[
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'refresh',
              backgroundColor: const Color(0xFFFFDDBA).withValues(alpha: 0.9),
              elevation: 4,
              mini: true,
              onPressed: _reloadMap,
              child: const Icon(Icons.refresh, color: Colors.black87),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'locate',
              backgroundColor: const Color(0xFFD0E4FF).withValues(alpha: 0.9),
              elevation: 4,
              mini: true,
              onPressed: () {
                final pos = ref.read(currentLocationProvider).value;
                if (pos != null) {
                  _mapController.move(
                      LatLng(pos.latitude, pos.longitude), 15.0);
                }
              },
              child: const Icon(Icons.my_location, color: Colors.black87),
            ),
          ),

          // ── SOS button ──────────────────────────────────────────────────
          Positioned(
            bottom: _selectedAuto == null ? 120 : 350,
            left: 20,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: FloatingActionButton(
                heroTag: 'sos',
                backgroundColor: const Color(0xFFFF4B4B),
                elevation: 4,
                shape: const CircleBorder(),
                onPressed: _callSos,
                child: const Icon(Icons.call, color: Colors.white, size: 28),
              ),
            ),
          ),

          // ── Passenger action bar (Book Ride + Share Ride) ────────────────
          if ((ref.watch(currentUserProvider).value?.role ?? 'passenger') ==
              'passenger')
            Positioned(
              bottom: _selectedAuto == null ? 120 : 360,
              right: 20,
              child: _buildPassengerActionBar(rideAction),
            ),

          // ── Sliding Auto Details Sheet ───────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            bottom: _selectedAuto == null ? -400 : 0,
            left: 0,
            right: 0,
            height: 350,
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

  // ── Passenger Action Bar ───────────────────────────────────────────────────

  /// Column of two small FABs:
  /// - Book Ride (🛺) / Cancel (✕)
  /// - Share Ride (🤝) toggle
  Widget _buildPassengerActionBar(RideActionState rideAction) {
    final isLoading = rideAction.status == RideActionStatus.loading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Ride-Share toggle ────────────────────────────────────────
        FloatingActionButton.small(
          heroTag: 'share_ride',
          tooltip: rideAction.isSharing
              ? 'Disable Ride-Share'
              : 'Enable Ride-Share',
          backgroundColor: rideAction.isSharing
              ? Colors.teal
              : Colors.white.withValues(alpha: 0.9),
          onPressed: isLoading
              ? null
              : () async {
                  final ctrl =
                      ref.read(rideActionControllerProvider.notifier);
                  if (rideAction.isSharing) {
                    await ctrl.disableRideShare();
                  } else {
                    // Pass null destination — user can expand this later
                    await ctrl.enableRideShare();
                  }
                },
          child: Text(
            '🤝',
            style: TextStyle(fontSize: rideAction.isSharing ? 18 : 16),
          ),
        ),
        const SizedBox(height: 8),

        // ── Book / Cancel Ride ────────────────────────────────────────
        FloatingActionButton.extended(
          heroTag: 'book_ride',
          backgroundColor: rideAction.isRequesting
              ? Colors.red.shade400
              : const Color(0xFF007AFF),
          elevation: 4,
          onPressed: isLoading
              ? null
              : () async {
                  final ctrl =
                      ref.read(rideActionControllerProvider.notifier);
                  if (rideAction.isRequesting) {
                    await ctrl.cancelRide();
                  } else {
                    await ctrl.bookRide();
                  }
                },
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(
                  rideAction.isRequesting ? Icons.close : Icons.hail,
                  color: Colors.white,
                ),
          label: Text(
            rideAction.isRequesting ? 'Cancel' : 'Book Ride',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ── Custom bottom bar ──────────────────────────────────────────────────────

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
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTabItem(0, 'Map', Icons.place),
                  _buildTabItem(1, 'Activity', Icons.notes),
                  _buildTabItem(2, 'Profile', Icons.person),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label, IconData icon) {
    bool isSelected = _currentIndex == index;
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
            Icon(
              icon,
              color: isSelected
                  ? activeColor
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.grey[600]),
              size: 20,
            ),
            if (isSelected)
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: activeColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
