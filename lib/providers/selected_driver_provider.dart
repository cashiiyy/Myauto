import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nearby_driver_model.dart';

/// Holds the currently selected driver on the passenger map view.
/// Set when passenger taps a vehicle marker; cleared on ride creation or dismiss.
final selectedDriverProvider = StateProvider<NearbyDriverModel?>((ref) => null);
