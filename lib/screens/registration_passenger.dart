import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';
import 'permission_gate_screen.dart';

class RegistrationPassengerScreen extends ConsumerStatefulWidget {
  const RegistrationPassengerScreen({super.key});

  @override
  ConsumerState<RegistrationPassengerScreen> createState() => _RegistrationPassengerScreenState();
}

class _RegistrationPassengerScreenState extends ConsumerState<RegistrationPassengerScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  void _register() async {
    final notifier = ref.read(authControllerProvider.notifier);
    final cred = await notifier.signUpWithEmail(_emailCtrl.text.trim(), _passCtrl.text.trim());
    
    if (cred != null && cred.user != null) {
      final user = UserModel(
        uid: cred.user!.uid,
        email: _emailCtrl.text.trim(),
        role: 'passenger',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        createdAt: DateTime.now(),
        isVerified: false,
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
      appBar: AppBar(title: const Text('Passenger Registration'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 16),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
            const SizedBox(height: 16),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email address')),
            const SizedBox(height: 16),
            TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: isLoading ? null : _register,
              child: isLoading ? const CircularProgressIndicator() : const Text('Register & Verify'),
            )
          ],
        ),
      ),
    );
  }
}
