import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import 'permission_gate_screen.dart';
import 'login_screen.dart';
import 'registration_passenger.dart';
import 'registration_driver.dart';
import 'driver_details_intro_screen.dart';

class GetStartedScreen extends ConsumerStatefulWidget {
  const GetStartedScreen({super.key});

  @override
  ConsumerState<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends ConsumerState<GetStartedScreen>
    with SingleTickerProviderStateMixin {
  bool isPassenger = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onContinueWithEmail() {
    ref.read(userProfileProvider.notifier).updateProfileMode(
          isPassenger ? 'Passenger mode' : 'Driver mode',
        );
    if (isPassenger) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const RegistrationPassengerScreen()));
    } else {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const RegistrationDriverScreen()));
    }
  }

  void _onContinueWithGoogle() async {
    ref.read(userProfileProvider.notifier).updateProfileMode(
          isPassenger ? 'Passenger mode' : 'Driver mode',
        );
    final notifier = ref.read(authControllerProvider.notifier);
    final cred = await notifier.signInWithGoogle();
    if (!mounted) return;
    if (cred != null && cred.user != null) {
      // 1. Try to fetch existing user profile
      UserModel? existingUser = await notifier.getUserDocument(cred.user!.uid);
      
      UserModel user;

      if (existingUser != null) {
        user = existingUser;
      } else {
        // 2. Creates initial shell if totally new
        user = UserModel(
          uid: cred.user!.uid,
          email: cred.user!.email ?? '',
          role: isPassenger ? 'passenger' : 'driver',
          name: cred.user!.displayName ?? 'Google User',
          phone: '',
          createdAt: DateTime.now(),
          isVerified: true,
        );
      }

      // Save to local session
      ref.read(localSessionProvider.notifier).state = user;
      
      // Save shell immediately (unless we need to wait for driver details? 
      // Saving shell is fine, the driver details screen will update it).
      if (existingUser == null) {
        await notifier.createUserDocument(user);
      }
      
      if (!mounted) return;

      // 3. Conditional routing
      if (user.role == 'driver' && (user.autoRegistrationNumber == null || user.autoRegistrationNumber!.isEmpty)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DriverDetailsIntroScreen(user: user)),
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PermissionGateScreen()),
          (route) => false,
        );
      }
    } else {
      final error = ref.read(authControllerProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: $error')),
        );
      }
    }
  }

  void _onContinueWithPhone() {
    ref.read(userProfileProvider.notifier).updateProfileMode(
          isPassenger ? 'Passenger mode' : 'Driver mode',
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Phone Sign-In coming soon! Use Email for now.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Faint watermark background text
          // Faint watermark background text perfectly centered
          Center(
            child: Text(
              'My Auto',
              style: GoogleFonts.mysteryQuest(
                fontSize: 90,
                color: Colors.black.withValues(alpha: 0.04),
              ),
            ),
          ),


          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(flex: 2),

                      // Auto image centered
                      Center(
                        child: Image.asset(
                          'assets/images/auto.png',
                          width: 100,
                          height: 100,
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, _, __) =>
                              const Text('🛺', style: TextStyle(fontSize: 72)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      Center(
                        child: Text(
                          'Get Started',
                          style: GoogleFonts.inter(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Subtitle
                      Center(
                        child: Text(
                          'Login or Sign up to find your ride',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),

                      const SizedBox(height: 36),

                      // "I am a..." label
                      Text(
                        'I am a...',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Role toggle buttons – full width, side by side
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: isPassenger
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF007AFF)
                                              .withValues(alpha: 0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        )
                                      ]
                                    : [],
                              ),
                              child: ElevatedButton(
                                onPressed: () =>
                                    setState(() => isPassenger = true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isPassenger
                                      ? const Color(0xFF007AFF)
                                      : Colors.grey[200],
                                  foregroundColor: isPassenger
                                      ? Colors.white
                                      : Colors.black54,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Passenger',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: !isPassenger
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFFF9500)
                                              .withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        )
                                      ]
                                    : [],
                              ),
                              child: ElevatedButton(
                                onPressed: () =>
                                    setState(() => isPassenger = false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: !isPassenger
                                      ? const Color(0xFFFF9500)
                                      : Colors.grey[200],
                                  foregroundColor: !isPassenger
                                      ? Colors.white
                                      : Colors.black54,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Driver',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // Continue buttons
                      _buildContinueButton(
                        label: 'Continue with Google',
                        iconPath: 'assets/images/google_icon.png',
                        fallbackIcon: Icons.g_mobiledata_rounded,
                        onTap: _onContinueWithGoogle,
                      ),
                      const SizedBox(height: 14),
                      _buildContinueButton(
                        label: 'Continue with Email',
                        fallbackIcon: Icons.email_outlined,
                        onTap: _onContinueWithEmail,
                      ),
                      const SizedBox(height: 14),
                      _buildContinueButton(
                        label: 'Continue with Phone Number',
                        fallbackIcon: Icons.phone_outlined,
                        onTap: _onContinueWithPhone,
                      ),

                      const Spacer(flex: 3),

                      // "Already have an account?" link
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                            );
                          },
                          child: Text(
                            'Already have an account? Login',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF007AFF),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton({
    required String label,
    String? iconPath,
    required IconData fallbackIcon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.18),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(fallbackIcon, size: 20, color: Colors.black54),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
