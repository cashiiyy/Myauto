import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a destination selected by a passenger from the search bar.
///
/// This model is ADDITIVE ONLY — it has no connection to the existing booking,
/// matching, fare, payment, or ride-status logic. Selecting a destination
/// does not trigger a ride request or change any driver state.
class DestinationPlace {
  final String displayLabel;
  final String placeName;
  final double latitude;
  final double longitude;

  const DestinationPlace({
    required this.displayLabel,
    required this.placeName,
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() =>
      'DestinationPlace(label=$displayLabel, lat=$latitude, lng=$longitude)';
}

// ═══════════════════════════════════════════════════════════════════════════
// WARNING: This provider is READ-ONLY for destination selection ONLY.
//
// It MUST NOT trigger ride requests, bookings, or driver matching.
// It MUST NOT be read by: ride_action_provider, backend_drivers_provider,
//   backend_client_provider, rtdb_provider, or any ride lifecycle provider.
//
// Booking logic remains EXCLUSIVELY in the existing providers:
//   - lib/providers/ride_action_provider.dart  (booking flow)
//   - lib/providers/backend_drivers_provider.dart  (driver matching)
//   - lib/services/backend/api_client.dart  (ride API calls)
//
// The ONLY permitted consumers of destinationProvider are:
//   - lib/widgets/destination_search_bar.dart  (writes: set / clear)
//   - lib/screens/home_screen.dart  (reads: show pin marker on map)
// ═══════════════════════════════════════════════════════════════════════════

/// Holds the passenger's currently selected destination.
///
/// - null  : no destination selected (default state)
/// - non-null : a [DestinationPlace] the passenger typed and tapped
final destinationProvider = StateProvider<DestinationPlace?>((ref) => null);
