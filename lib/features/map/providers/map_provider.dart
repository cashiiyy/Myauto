import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../models/auto_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/backend_drivers_provider.dart';
import '../../../providers/destination_provider.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/ride_action_provider.dart';
import '../../../providers/rtdb_provider.dart';
import '../../../providers/selected_driver_provider.dart';
import '../../../services/routing/routing_service.dart';
import '../services/marker_service.dart';

/// Provider for selected auto model on the map (used by auto details sheet).
final selectedAutoProvider = StateProvider<AutoModel?>((ref) => null);

/// Calculates the route polyline and ETA for passenger between GPS location and destination.
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

/// Computes the visual [Set<Polyline>] for Google Maps based on active route state.
final polylineProvider = Provider<Set<Polyline>>((ref) {
  final routeAsync = ref.watch(routeProvider);
  return routeAsync.maybeWhen(
    data: (route) {
      if (route == null || route.polyline.isEmpty) return <Polyline>{};
      return <Polyline>{
        Polyline(
          polylineId: const PolylineId('myauto_route_polyline'),
          points: route.polyline,
          width: 5,
          color: const Color(0xFF2563EB),
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      };
    },
    orElse: () => <Polyline>{},
  );
});

/// High-performance [Set<Marker>] provider that aggregates all 5 marker sources:
/// 1. Nearby Auto Drivers ([backendDriversProvider])
/// 2. Current User Position ([currentLocationProvider])
/// 3. Passenger Destination Pin ([destinationProvider])
/// 4. RTDB Co-Passenger Ride Shares ([nearbyRideSharesStreamProvider])
/// 5. Driver-side Incoming Request Pulse ([incomingRideRequestProvider])
///
/// Uses pre-cached [BitmapDescriptor]s from [MarkerService] to guarantee
/// zero asset decoding during GPS or WebSocket location updates.
final markersProvider = Provider<Set<Marker>>((ref) {
  final markerServiceAsync = ref.watch(markerServiceProvider);

  // Return empty set while marker assets are loading asynchronously
  final markerService = markerServiceAsync.value;
  if (markerService == null || !markerService.isInitialized) {
    return <Marker>{};
  }

  final driversState = ref.watch(backendDriversProvider);
  final posAsync = ref.watch(currentLocationProvider);
  final dest = ref.watch(destinationProvider);
  final sharesAsync = ref.watch(nearbyRideSharesStreamProvider);
  final incomingRequest = ref.watch(incomingRideRequestProvider);
  final selectedDriver = ref.watch(selectedDriverProvider);
  final currentUser = ref.watch(currentUserProvider).value;

  final userRole = (currentUser?.role ?? 'passenger').toLowerCase();
  final shares = sharesAsync.value ?? const [];

  return markerService.buildMarkers(
    drivers: driversState.drivers,
    currentPosition: posAsync.value,
    destination: dest,
    rideShares: shares,
    incomingRequest: incomingRequest,
    selectedDriverUid: selectedDriver?.driverUid,
    userRole: userRole,
    onDriverSelected: (driver) {
      ref.read(selectedDriverProvider.notifier).state = driver;
      
      final auto = AutoModel(
        id: driver.driverUid,
        latitude: driver.latitude,
        longitude: driver.longitude,
        isAvailable: driver.isAvailable,
        driverName: 'Auto Driver',
        phoneNumber: '',
        vehicleNumber: 'KL Auto',
        rating: driver.rating ?? 5.0,
      );
      ref.read(selectedAutoProvider.notifier).state = auto;
    },
    onShareSelected: (share) {
      debugPrint('[Map] Selected co-passenger share: ${share.name}');
    },
  );
});
