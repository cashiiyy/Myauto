import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/ws_provider.dart';

class DebugDiagnosticsScreen extends ConsumerWidget {
  const DebugDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wsStateAsync = ref.watch(wsConnectionStateProvider);
    final userAsync = ref.watch(currentUserProvider);
    final authStateAsync = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Debug Diagnostics',
          style: GoogleFonts.fustat(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('API Configuration'),
          _buildInfoCard(
            context,
            'REST API Base URL',
            AppConfig.backendUrl,
            Icons.http,
          ),
          _buildInfoCard(
            context,
            'WebSocket Base URL',
            AppConfig.backendWsUrl,
            Icons.swap_calls,
          ),
          _buildInfoCard(
            context,
            'Mock Mode Enabled',
            AppConfig.mockMode ? 'TRUE' : 'FALSE',
            Icons.developer_mode,
            valueColor: AppConfig.mockMode ? Colors.orange : Colors.grey,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Connection Status'),
          wsStateAsync.when(
            data: (state) => _buildInfoCard(
              context,
              'WebSocket State',
              state.name.toUpperCase(),
              Icons.wifi,
              valueColor: state == WsConnectionState.connected
                  ? Colors.green
                  : Colors.red,
            ),
            loading: () => _buildInfoCard(
              context,
              'WebSocket State',
              'LOADING...',
              Icons.wifi_protected_setup,
            ),
            error: (err, _) => _buildInfoCard(
              context,
              'WebSocket State',
              'ERROR: $err',
              Icons.error_outline,
              valueColor: Colors.red,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('User Authentication'),
          authStateAsync.when(
            data: (authUser) => _buildInfoCard(
              context,
              'Auth Status',
              authUser != null ? 'Authenticated' : 'Not Authenticated',
              Icons.lock_open,
              valueColor: authUser != null ? Colors.green : Colors.red,
            ),
            loading: () => _buildInfoCard(context, 'Auth Status', 'LOADING...', Icons.lock),
            error: (err, _) => _buildInfoCard(context, 'Auth Status', 'ERROR: $err', Icons.error),
          ),
          userAsync.when(
            data: (user) {
              if (user == null) {
                return _buildInfoCard(
                  context,
                  'User Profile',
                  'No Profile Loaded',
                  Icons.person_off,
                  valueColor: Colors.orange,
                );
              }
              return Column(
                children: [
                  _buildInfoCard(
                    context,
                    'User UID',
                    user.uid,
                    Icons.fingerprint,
                  ),
                  _buildInfoCard(
                    context,
                    'User Role',
                    user.role.toUpperCase(),
                    Icons.assignment_ind,
                    valueColor: user.role == 'driver' ? Colors.amber : Colors.blue,
                  ),
                  _buildInfoCard(
                    context,
                    'User Email',
                    user.email,
                    Icons.email,
                  ),
                ],
              );
            },
            loading: () => _buildInfoCard(context, 'User Profile', 'LOADING...', Icons.person),
            error: (err, _) => _buildInfoCard(context, 'User Profile', 'ERROR: $err', Icons.error),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: GoogleFonts.fustat(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: SelectableText(
          value,
          style: GoogleFonts.fustat(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}
