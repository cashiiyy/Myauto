import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import 'permission_gate_screen.dart';
import 'registration_passenger.dart';
import 'registration_driver.dart';
import 'driver_details_intro_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  void _login() async {
    final notifier = ref.read(authControllerProvider.notifier);
    await notifier.loginWithEmail(
      _emailCtrl.text.trim(), 
      _passCtrl.text.trim(),
    );
    final error = ref.read(authControllerProvider).error;
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } else {
      final fbUser = ref.read(firebaseAuthProvider)?.currentUser;
      UserModel? user;
      if (fbUser != null) {
        user = await notifier.getUserDocument(fbUser.uid);
      }
      
      // Fallback if user document doesn't exist or we are in mock mode
      user ??= UserModel(
        uid: fbUser?.uid ?? 'email_user',
        email: _emailCtrl.text.trim(),
        role: 'passenger',
        name: fbUser?.displayName ?? _emailCtrl.text.split('@').first,
        phone: '',
        createdAt: DateTime.now(),
      );

      // Save local session
      ref.read(localSessionProvider.notifier).state = user;
      
      if (!mounted) return;
      
      // Route based on role and registration completion if driver
      if (user.role == 'driver' && (user.autoRegistrationNumber == null || user.autoRegistrationNumber!.isEmpty)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DriverDetailsIntroScreen(user: user!)),
        );
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PermissionGateScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/images/auto.png', height: 100),
              const SizedBox(height: 24),
              Text(
                'Welcome Back',
                style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                ),
                child: isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              // Setup quick access to registration nodes
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationPassengerScreen())),
                child: const Text('Register as Passenger'),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationDriverScreen())),
                child: const Text('Register as Driver', style: TextStyle(color: Colors.orange)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
