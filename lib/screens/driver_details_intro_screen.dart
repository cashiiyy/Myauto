import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';
import 'permission_gate_screen.dart';

class DriverDetailsIntroScreen extends ConsumerStatefulWidget {
  final UserModel user;
  const DriverDetailsIntroScreen({super.key, required this.user});

  @override
  ConsumerState<DriverDetailsIntroScreen> createState() => _DriverDetailsIntroScreenState();
}

class _DriverDetailsIntroScreenState extends ConsumerState<DriverDetailsIntroScreen> {
  final _vehicleCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  bool _isLoading = false;

  void _saveDetailsAndContinue() async {
    if (_vehicleCtrl.text.trim().isEmpty || _licenseCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all required details')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Update the local session user with new details
    final updatedUser = UserModel(
      uid: widget.user.uid,
      email: widget.user.email,
      role: 'driver',
      name: widget.user.name,
      phone: widget.user.phone,
      createdAt: widget.user.createdAt,
      isVerified: widget.user.isVerified,
      autoRegistrationNumber: _vehicleCtrl.text.trim(),
      licenseNumber: _licenseCtrl.text.trim(),
    );

    // Save properly using the authController
    final notifier = ref.read(authControllerProvider.notifier);
    await notifier.createUserDocument(updatedUser);
    
    // Update local state
    ref.read(localSessionProvider.notifier).state = updatedUser;

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PermissionGateScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Driver Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Almost ready to drive! 🛺',
                style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Please provide your vehicle and license details to get started on the platform.',
                style: GoogleFonts.inter(fontSize: 15, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _vehicleCtrl,
                decoration: InputDecoration(
                  labelText: 'Auto Registration Number (e.g. KL-01-AB-1234)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _licenseCtrl,
                decoration: InputDecoration(
                  labelText: 'Driving License Number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveDetailsAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9500),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                      : Text('Save & Continue', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
