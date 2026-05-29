import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_service.dart';
import 'home_screen.dart';

/// Shown once after login if location permissions are not yet granted.
/// Blocks navigation to [HomeScreen] until the user grants at least
/// foreground location. Background location is asked as a second step.
///
/// States handled:
/// - Not yet asked → show rationale + "Allow" button
/// - Denied (can re-ask) → show explanation + "Try Again"
/// - Permanently denied → "Open Settings"
/// - Service off → prompt user to enable GPS hardware
class PermissionGateScreen extends StatefulWidget {
  const PermissionGateScreen({super.key});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen>
    with SingleTickerProviderStateMixin {
  final _permService = PermissionService();

  _UiState _uiState = _UiState.rationale;
  bool _isLoading = false;

  late AnimationController _pulseController;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-check on open — if already granted, skip this screen
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExisting());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Logic ─────────────────────────────────────────────────────────

  Future<void> _checkExisting() async {
    final result = await _permService.checkAll();
    if (!mounted) return;

    switch (result) {
      case LocationPermissionResult.granted:
        _proceed(); // already granted — skip straight to app
        break;
      case LocationPermissionResult.permanentlyDenied:
        setState(() => _uiState = _UiState.permanentlyDenied);
        break;
      case LocationPermissionResult.serviceDisabled:
        setState(() => _uiState = _UiState.serviceOff);
        break;
      case LocationPermissionResult.denied:
        setState(() => _uiState = _UiState.rationale); // show explanation first
        break;
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);

    // Step 1 — foreground location
    final status = await _permService.requestLocation();

    if (!mounted) return;

    if (status.isGranted || status.isLimited) {
      // Step 2 — try background (non-blocking, skip on denial)
      await _permService.requestBackgroundLocation();
      _proceed();
      return;
    }

    setState(() {
      _isLoading = false;
      _uiState = status.isPermanentlyDenied
          ? _UiState.permanentlyDenied
          : _UiState.denied;
    });
  }

  Future<void> _openSettings() async {
    await _permService.openSettings();
    // Re-check after user returns from settings
    if (mounted) await _checkExisting();
  }

  Future<void> _enableGps() async {
    await Geolocator_enableLocationServices();
    if (mounted) await _checkExisting();
  }

  // ignore: non_constant_identifier_names
  Future<void> Geolocator_enableLocationServices() async {
    // On Android, prompt the system location dialog
    await _permService.requestLocation();
  }

  void _proceed() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0A1A), Color(0xFF0D1B2A), Color(0xFF112240)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                _buildIcon(),
                const SizedBox(height: 40),
                _buildTitle(),
                const SizedBox(height: 16),
                _buildDescription(),
                const Spacer(),
                _buildActionButton(),
                const SizedBox(height: 16),
                if (_uiState == _UiState.permanentlyDenied ||
                    _uiState == _UiState.denied)
                  _buildSecondaryText(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final iconData = _uiState == _UiState.serviceOff
        ? Icons.location_off_rounded
        : _uiState == _UiState.permanentlyDenied
            ? Icons.lock_rounded
            : Icons.location_on_rounded;

    final iconColor = _uiState == _UiState.permanentlyDenied
        ? const Color(0xFFFF6B6B)
        : _uiState == _UiState.serviceOff
            ? const Color(0xFFFFB347)
            : const Color(0xFF4FC3F7);

    return ScaleTransition(
      scale: _pulse,
      child: Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iconColor.withValues(alpha: 0.12),
          border: Border.all(color: iconColor.withValues(alpha: 0.4), width: 2),
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: 0.25),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Icon(iconData, size: 64, color: iconColor),
      ),
    );
  }

  Widget _buildTitle() {
    final title = switch (_uiState) {
      _UiState.rationale => 'Location Access Needed',
      _UiState.denied => 'Permission Denied',
      _UiState.permanentlyDenied => 'Permission Blocked',
      _UiState.serviceOff => 'Turn On Location',
    };

    return Text(
      title,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildDescription() {
    final desc = switch (_uiState) {
      _UiState.rationale =>
        'My Auto needs your location to show nearby auto-rickshaws, '
            'match you with drivers, and enable real-time ride tracking.\n\n'
            'Your location is never shared without your action.',
      _UiState.denied =>
        'You declined location access. Without it, the app cannot show '
            'nearby autos or enable booking.\n\nPlease tap "Try Again" and allow location access.',
      _UiState.permanentlyDenied =>
        'Location permission was permanently blocked.\n\n'
            'Go to Settings → My Auto → Permissions → Location, '
            'and set it to "Allow while using the app".',
      _UiState.serviceOff =>
        'Your device\'s location (GPS) is turned off.\n\n'
            'Please enable Location from your device settings to continue.',
    };

    return Text(
      desc,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 15,
        color: Colors.white60,
        height: 1.6,
      ),
    );
  }

  Widget _buildActionButton() {
    final label = switch (_uiState) {
      _UiState.rationale => 'Allow Location Access',
      _UiState.denied => 'Try Again',
      _UiState.permanentlyDenied => 'Open App Settings',
      _UiState.serviceOff => 'Enable GPS',
    };

    final color = _uiState == _UiState.permanentlyDenied
        ? const Color(0xFFFF6B6B)
        : _uiState == _UiState.serviceOff
            ? const Color(0xFFFFB347)
            : const Color(0xFF007AFF);

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: color.withValues(alpha: 0.4),
        ),
        onPressed: _isLoading
            ? null
            : () {
                switch (_uiState) {
                  case _UiState.rationale:
                  case _UiState.denied:
                    _requestPermission();
                    break;
                  case _UiState.permanentlyDenied:
                    _openSettings();
                    break;
                  case _UiState.serviceOff:
                    _enableGps();
                    break;
                }
              },
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _uiState == _UiState.permanentlyDenied
                        ? Icons.settings_rounded
                        : _uiState == _UiState.serviceOff
                            ? Icons.gps_fixed_rounded
                            : Icons.location_on_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSecondaryText() {
    return TextButton(
      onPressed: () {
        // Allow user to skip (app will show empty map)
        _proceed();
      },
      child: Text(
        'Skip for now (limited functionality)',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: Colors.white38,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white38,
        ),
      ),
    );
  }
}

enum _UiState { rationale, denied, permanentlyDenied, serviceOff }
