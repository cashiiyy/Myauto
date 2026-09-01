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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Estimated arrival time based on distance (approx 2.5 min per km + 1 min base)
    final etaMinutes = (distance * 2.5 + 1.0).clamp(2.0, 45.0).round();

    // Estimated fare (Base ₹30 + ₹15/km, minimum ₹30)
    final estimatedFare = (30.0 + (distance * 15.0)).round().clamp(30, 999);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Row: Driver / Vehicle info & Close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                    ),
                    child: const Center(
                      child: Icon(Icons.electric_rickshaw_rounded, size: 30, color: Color(0xFFB45309)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            auto.driverName.isNotEmpty && auto.driverName != 'Driver'
                                ? auto.driverName
                                : 'Kerala Auto',
                            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF2563EB)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            auto.vehicleNumber.isNotEmpty ? auto.vehicleNumber : 'KL Auto',
                            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade300, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                const SizedBox(width: 3),
                                Text(
                                  '${auto.rating}',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: onClose,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: const CircleBorder(),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Stats Chips: Distance, ETA, Availability
          Row(
            children: [
              // Distance
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.near_me_rounded, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 6),
                      Text(
                        '${distance.toStringAsFixed(1)} km',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ETA
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFFD97706)),
                      const SizedBox(width: 6),
                      Text(
                        '~$etaMinutes mins',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Availability Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: auto.isAvailable
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: auto.isAvailable ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                  ),
                ),
                child: Text(
                  auto.isAvailable ? 'AVAILABLE' : 'BUSY',
                  style: GoogleFonts.inter(
                    color: auto.isAvailable ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          // Destination Dropoff Banner (if active)
          if (destination != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded, size: 18, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Destination: ${destination.displayLabel}',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E3A8A), fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '~₹$estimatedFare',
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E3A8A), fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action Buttons: Call & Book Ride
          Row(
            children: [
              if (auto.phoneNumber.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: _callDriver,
                  icon: const Icon(Icons.call_rounded, color: Color(0xFF16A34A), size: 18),
                  label: Text('Call', style: GoogleFonts.inter(color: const Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(width: 12),
              ],

              Expanded(
                child: ElevatedButton(
                  onPressed: (isBooking || !auto.isAvailable) ? null : () => _bookNow(context, ref),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isBooking
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            Text('Connecting...', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        )
                      : Text(
                          auto.isAvailable ? 'Request This Auto' : 'Auto Unavailable',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
