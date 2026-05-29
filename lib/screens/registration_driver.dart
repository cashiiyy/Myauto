import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';
import 'permission_gate_screen.dart';

class RegistrationDriverScreen extends ConsumerStatefulWidget {
  const RegistrationDriverScreen({super.key});

  @override
  ConsumerState<RegistrationDriverScreen> createState() => _RegistrationDriverScreenState();
}

class _RegistrationDriverScreenState extends ConsumerState<RegistrationDriverScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _autoRegCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  // Mocking photo uploads since Web image_picker + storage bounds require deep setup
  String? _mockDriverPhotoUrl;
  String? _mockAutoPhotoUrl;

  void _register() async {
    final notifier = ref.read(authControllerProvider.notifier);
    final cred = await notifier.signUpWithEmail(_emailCtrl.text.trim(), _passCtrl.text.trim());
    
    if (cred != null && cred.user != null) {
      final user = UserModel(
        uid: cred.user!.uid,
        email: _emailCtrl.text.trim(),
        role: 'driver',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        createdAt: DateTime.now(),
        isVerified: false,
        autoRegistrationNumber: _autoRegCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
        driverPhotoUrl: _mockDriverPhotoUrl,
        autoPhotoUrl: _mockAutoPhotoUrl,
        isAvailable: true,
        latitude: 0.0,
        longitude: 0.0,
      );
      
      await notifier.createUserDocument(user);
      // Save to local session for Mock Mode profile display
      ref.read(localSessionProvider.notifier).state = user;

      if(!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const PermissionGateScreen()), (route) => false);
    } else {
      final error = ref.read(authControllerProvider).error;
      if(!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      } else {
        // Mock mode: proceed to home
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const PermissionGateScreen()), (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Registration', style: TextStyle(color: Colors.orange)), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 16),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
            const SizedBox(height: 16),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email Address')),
            const SizedBox(height: 16),
            TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const Divider(height: 48),
            
            TextField(controller: _autoRegCtrl, decoration: const InputDecoration(labelText: 'Auto Registration Number (e.g., KL-01-AB-1234)')),
            const SizedBox(height: 16),
            TextField(controller: _licenseCtrl, decoration: const InputDecoration(labelText: 'Driving License Number')),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _mockDriverPhotoUrl = 'uploaded_driver.jpg');
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver Photo attached (Simulated)')));
                    },
                    icon: Icon(_mockDriverPhotoUrl != null ? Icons.check : Icons.camera_alt),
                    label: const Text('Driver Photo'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _mockAutoPhotoUrl = 'uploaded_auto.jpg');
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auto Photo attached (Simulated)')));
                    },
                    icon: Icon(_mockAutoPhotoUrl != null ? Icons.check : Icons.camera_alt),
                    label: const Text('Auto Photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),

            ElevatedButton(
              onPressed: isLoading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: isLoading ? const CircularProgressIndicator() : const Text('Register & Go Online', style: TextStyle(fontSize: 18)),
            )
          ],
        ),
      ),
    );
  }
}
