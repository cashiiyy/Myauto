import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'activity_details_screen.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Reacts to theme
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Recent Activity',
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 30),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Optional Background aesthetic element if needed
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withValues(alpha: 0.1),
                boxShadow: const [BoxShadow(blurRadius: 100, color: Colors.amber)],
              ),
            ),
          ),
          
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              _buildActivityCard(
                context,
                title: 'Ride to MG Road',
                date: 'Yesterday, 4:30 PM',
                amount: '₹120',
                distance: '8.2 km',
                icon: '🛺',
              ),
              
              const SizedBox(height: 48),
              
              // Empty State simulated to look dynamic
              Center(
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 60, color: Colors.grey.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(
                      "No older activity found.",
                      style: GoogleFonts.inter(fontSize: 16, color: Colors.grey.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 100), // padding for bottom bar
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(
    BuildContext context, {
    required String title,
    required String date,
    required String amount,
    required String distance,
    required String icon,
    bool isCancelled = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: isDark ? const Color(0xFF262626) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActivityDetailsScreen(
                  title: title,
                  date: date,
                  amount: amount,
                  distance: distance,
                  isCancelled: isCancelled,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.2),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCancelled
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.amber.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: isCancelled
                      ? Text(icon, style: const TextStyle(fontSize: 24))
                      : Image.asset('assets/images/rickshaw (1).png',
                          width: 28, height: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.fustat(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$date · $amount · $distance',
                        style: GoogleFonts.abel(
                          fontSize: 15,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ),
    );

  }
}
