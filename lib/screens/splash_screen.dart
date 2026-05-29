import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'get_started_screen.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'permission_gate_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _textFadeController;
  late AnimationController _autoSlideController;
  
  late Animation<double> _textFadeIn;
  late Animation<Offset> _autoSlideIn;

  @override
  void initState() {
    super.initState();
    
    // Controller for the "My Auto" text fade
    _textFadeController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1000)
    );
    _textFadeIn = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _textFadeController, curve: Curves.easeIn));

    // Controller for the Auto sliding from right to center
    _autoSlideController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1200)
    );
    _autoSlideIn = Tween<Offset>(begin: const Offset(2.0, 0.0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _autoSlideController, curve: Curves.easeOutCubic));

    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    // 1. Fade in the text
    await _textFadeController.forward();
    
    // Hold the text for a moment
    await Future.delayed(const Duration(milliseconds: 500));
    
    // 2. Slide the auto in from the RIGHT to the center
    await _autoSlideController.forward();
    
    // 3. Text disappears
    await _textFadeController.reverse();
    
    // Hold the final state (just auto)
    await Future.delayed(const Duration(milliseconds: 600));

    // 4. Dissolve completely into the appropriate screen
    if (mounted) {
      final authUser = ref.read(authStateProvider).value;
      
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => 
              authUser != null ? const PermissionGateScreen() : const GetStartedScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 1000), // smooth dissolve
        )
      );
    }
  }

  @override
  void dispose() {
    _textFadeController.dispose();
    _autoSlideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Pure black as requested
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The text that fades in first
            FadeTransition(
              opacity: _textFadeIn,
              child: Text(
                'My Auto',
                style: GoogleFonts.mysteryQuest(
                  fontSize: 54,
                  color: Colors.white,
                ),
              ),
            ),
            
            // The auto that slides in from the left on top of the text
            SlideTransition(
              position: _autoSlideIn,
              child: Image.asset(
                'assets/images/auto.png', 
                width: 120, // Smaller icon size based on the user's reference image
                fit: BoxFit.contain, 
                errorBuilder: (ctx, _, __) => const Text('🛺', style: TextStyle(fontSize: 80))
              ),
            ),
          ],
        ),
      ),
    );
  }
}
