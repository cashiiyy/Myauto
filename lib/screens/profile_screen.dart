import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

import 'edit_profile_screen.dart';
import 'safety_contacts_screen.dart';
import 'settings_screen.dart';
import 'offers_screen.dart';
import 'get_started_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: userAsync.when(
          data: (user) {
            if (user == null) {
              return const Center(child: Text('Not logged in'));
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                      onPressed: () {
                        ref.read(themeModeProvider.notifier).state = 
                            isDark ? ThemeMode.light : ThemeMode.dark;
                      },
                    ),
                  ),
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 120, height: 120,
                          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                        ),
                        if (user.driverPhotoUrl != null) 
                          ClipOval(child: Image.network(user.driverPhotoUrl!, width: 120, height: 120, fit: BoxFit.cover))
                        else
                          ColorFiltered(
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                            child: Image.asset('assets/images/Profile.png', width: 60, height: 60, fit: BoxFit.contain, 
                               errorBuilder: (ctx, err, constr) => const Icon(Icons.person, color: Colors.white, size: 60)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.role == 'driver' ? 'Driver Mode' : 'Passenger Mode',
                    style: GoogleFonts.abel(fontSize: 16, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 32),

              _buildMenuCard(context, 'Edit Profile', 'assets/images/Frame 10.png', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(user: user)));
              }),
              _buildMenuCard(context, 'Offers & Promos', 'assets/images/Tags.png', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const OffersScreen()));
              }),
              _buildMenuCard(context, 'Safety Contacts', 'assets/images/Contacts.png', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyContactsScreen()));
              }),
              _buildMenuCard(context, 'Settings', 'assets/images/Settings.png', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }),
              _buildMenuCard(context, 'Customer support', 'assets/images/customer-support-icon.png', () {}),
              
              const SizedBox(height: 32),
              Center(
                child: Container(
                  width: 200,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF383C), // Red Sign Out
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(27),
                      onTap: () async {
                        // Sign out and clear stack
                        await ref.read(authControllerProvider.notifier).signOut();
                        ref.read(localSessionProvider.notifier).state = null;
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context, 
                            MaterialPageRoute(builder: (_) => const GetStartedScreen()), 
                            (route) => false,
                          );
                        }
                      },
                      child: Center(
                        child: Text(
                          'Sign Out',
                          style: GoogleFonts.fustat(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 120), // padding for bottom bar
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    ),
  ),
);
  }

  Widget _buildMenuCard(BuildContext context, String label, String imagePath, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.7),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1.5),
                ),
                child: Row(
                  children: [
                    ColorFiltered(
                      colorFilter: isDark 
                          ? const ColorFilter.matrix([
                              -1, 0, 0, 0, 255, 
                              0, -1, 0, 0, 255, 
                              0, 0, -1, 0, 255, 
                              0, 0, 0, 1, 0]) // simple invert for dark mode
                          : const ColorFilter.mode(Colors.black, BlendMode.dstIn),
                      child: Image.asset(imagePath, width: 28, height: 28,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 28),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      label,
                      style: GoogleFonts.fustat(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
