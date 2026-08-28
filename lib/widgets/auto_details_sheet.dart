import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/auto_model.dart';
import '../models/nearby_driver_model.dart';
import '../providers/destination_provider.dart';
import '../providers/ride_action_provider.dart';
import '../providers/selected_driver_provider.dart';

class AutoDetailsSheet extends ConsumerWidget {
  final AutoModel auto;
  final double distance;
  final VoidCallback? onClose;

  const AutoDetailsSheet({
    super.key,
    required this.auto,
    required this.distance,
    this.onClose,
  });

  void _callDriver() async {
    if (auto.phoneNumber.isEmpty) return;
    final Uri url = Uri(scheme: 'tel', path: auto.phoneNumber);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _bookNow(BuildContext context, WidgetRef ref) async {
    if (!auto.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This auto is currently busy. Please select an available auto.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Set targeted driver in state
    ref.read(selectedDriverProvider.notifier).state = NearbyDriverModel(
      driverUid: auto.id,
      latitude: auto.latitude,
      longitude: auto.longitude,
      isAvailable: auto.isAvailable,
      rating: auto.rating,
      distanceKm: distance,
      freshness: 'LIVE',
    );

    // Trigger ride booking
    await ref.read(rideActionControllerProvider.notifier).bookRide();

    if (context.mounted) {
      final rideState = ref.read(rideActionControllerProvider);
      if (rideState.status == RideActionStatus.error && rideState.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(rideState.message!),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Booking request sent to driver! Waiting for confirmation...'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
        if (onClose != null) onClose!();
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideState = ref.watch(rideActionControllerProvider);
    final destination = ref.watch(destinationProvider);
    final isBooking = rideState.status == RideActionStatus.loading;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.amber.shade100,
                    radius: 24,
                    child: const Text('🛺', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auto.driverName.isNotEmpty && auto.driverName != 'Driver'
                            ? auto.driverName
                            : 'Auto Rickshaw',
                        style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        auto.vehicleNumber.isNotEmpty ? auto.vehicleNumber : 'Verified Auto',
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
              if (onClose != null) 
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.grey, size: 20),
              const SizedBox(width: 8),
              Text('${distance.toStringAsFixed(2)} km away', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: auto.isAvailable ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  auto.isAvailable ? 'Available' : 'Busy',
                  style: TextStyle(
                    color: auto.isAvailable ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (destination != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_outlined, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dropoff: ${destination.displayLabel}',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.blue.shade900, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              if (auto.phoneNumber.isNotEmpty) ...[
                Expanded(
                  flex: 1,
                  child: OutlinedButton.icon(
                    onPressed: _callDriver,
                    icon: const Icon(Icons.call, color: Colors.green),
                    label: const Text('Call', style: TextStyle(color: Colors.green)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.green),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: (isBooking || !auto.isAvailable) ? null : () => _bookNow(context, ref),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isBooking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Book Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
