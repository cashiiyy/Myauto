import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/backend/api_client.dart';

/// Provides the singleton [BackendApiClient].
///
/// In mock mode, the client bypasses all HTTP calls.
/// When the Firebase auth instance is unavailable (web testing without Firebase),
/// the client operates unauthenticated — the server will reject protected calls.
final backendApiClientProvider = Provider<BackendApiClient>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return BackendApiClient(auth: auth);
});
