import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';
import 'get_started_screen.dart';
import 'permission_gate_screen.dart';
import 'driver_details_intro_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _iconScaleAnim;
  late Animation<double> _iconFadeAnim;
  late Animation<double> _titleFadeAnim;
  late Animation<Offset> _titleSlideAnim;
  late Animation<double> _taglineFadeAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Staggered smooth animation curves with zero blocking delays
    _iconScaleAnim = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _iconFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );

    _titleFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
      ),
    );

    _titleSlideAnim =
        Tween<Offset>(begin: const Offset(0.0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _taglineFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.55, 0.95, curve: Curves.easeOut),
      ),
    );

    _runStartupSequence();
  }

  Future<Widget> _resolveTargetScreen() async {
    try {
      // 1. Resolve Auth State
      User? authUser = ref.read(authStateProvider).value;
      if (authUser == null && !ref.read(authStateProvider).hasValue) {
        try {
          authUser = await ref.read(authStateProvider.future);
        } catch (_) {
          authUser = ref.read(authStateProvider).value;
        }
      }

      if (authUser == null) {
        return const GetStartedScreen();
      }

      // 2. Resolve User Profile
      UserModel? userProfile = ref.read(currentUserProvider).value;
      if (userProfile == null && !ref.read(currentUserProvider).hasValue) {
        try {
          userProfile = await ref.read(currentUserProvider.future);
        } catch (_) {
          userProfile = ref.read(currentUserProvider).value;
        }
      }

      // 3. Driver vehicle details gate
      if (userProfile != null &&
          userProfile.role == 'driver' &&
          (userProfile.autoRegistrationNumber == null ||
              userProfile.autoRegistrationNumber!.isEmpty)) {
        return DriverDetailsIntroScreen(user: userProfile);
      }

      // 4. Default to PermissionGateScreen which gracefully transitions to HomeScreen
      return const PermissionGateScreen();
    } catch (e) {
      debugPrint('Startup resolution error: $e');
      return const GetStartedScreen();
    }
  }

  void _runStartupSequence() async {
    // 1. Play the smooth 1800ms entrance animation
    await _animController.forward();

    if (!mounted) return;

    // 2. Resolve destination screen
    final targetScreen = await _resolveTargetScreen();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Do NOT watch authStateProvider or currentUserProvider here
    // to prevent rebuilds and animation frame drops!
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium dark navy background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // High-resolution App Icon with subtle elevation & scale animation
            ScaleTransition(
              scale: _iconScaleAnim,
              child: FadeTransition(
                opacity: _iconFadeAnim,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00979E).withValues(alpha: 0.35),
                        blurRadius: 36,
                        spreadRadius: 2,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/auto.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // "My Auto" Title with smooth fade & slide
            SlideTransition(
              position: _titleSlideAnim,
              child: FadeTransition(
                opacity: _titleFadeAnim,
                child: Text(
                  'My Auto',
                  style: GoogleFonts.mysteryQuest(
                    fontSize: 48,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Tagline
            FadeTransition(
              opacity: _taglineFadeAnim,
              child: Text(
                'Real-Time Auto Discovery',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8), // Slate-400
                  letterSpacing: 2.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
