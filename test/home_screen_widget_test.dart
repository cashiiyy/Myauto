import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_auto/models/user_model.dart';
import 'package:my_auto/providers/auth_provider.dart';
import 'package:my_auto/providers/location_provider.dart';
import 'package:my_auto/providers/backend_client_provider.dart';
import 'package:my_auto/providers/ws_provider.dart';
import 'package:my_auto/services/backend/api_client.dart';
import 'package:my_auto/services/backend/ws_client.dart';
import 'package:my_auto/screens/home_screen.dart';
import 'package:my_auto/widgets/destination_search_bar.dart';
import 'dart:async';

class MockBackendApiClient extends BackendApiClient {
  MockBackendApiClient() : super(auth: null);
}

class MockBackendWebSocketClient extends BackendWebSocketClient {
  MockBackendWebSocketClient() : super(auth: null);
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void dispose() { super.dispose(); }
}

void main() {
  group('HomeScreen Widget Tests', () {
    testWidgets('Passenger role shows DestinationSearchBar', (WidgetTester tester) async {
      // Create a mock user model with passenger role
      final mockPassenger = UserModel(
        uid: 'pass_123',
        email: 'pass@test.com',
        phone: '+919999999999',
        role: 'passenger',
        name: 'Test Passenger',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(mockPassenger)),
            currentLocationProvider.overrideWith((ref) => const Stream.empty()),
            backendApiClientProvider.overrideWithValue(MockBackendApiClient()),
            wsClientProvider.overrideWithValue(MockBackendWebSocketClient()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      // We need to wait for the location async to settle or we can just assert it renders the loading overlay
      await tester.pump();

      // Because the location is loading, we should see the "Acquiring GPS location..." banner
      expect(find.text('Acquiring GPS location...'), findsOneWidget);

      // And we should also see the DestinationSearchBar because the map loading is now decoupled
      expect(find.byType(DestinationSearchBar), findsOneWidget);
    });

    testWidgets('Driver role hides DestinationSearchBar', (WidgetTester tester) async {
      // Create a mock user model with driver role
      final mockDriver = UserModel(
        uid: 'drv_123',
        email: 'drv@test.com',
        phone: '+918888888888',
        role: 'driver',
        name: 'Test Driver',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(mockDriver)),
            currentLocationProvider.overrideWith((ref) => const Stream.empty()),
            backendApiClientProvider.overrideWithValue(MockBackendApiClient()),
            wsClientProvider.overrideWithValue(MockBackendWebSocketClient()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      // Driver should NOT see the DestinationSearchBar
      expect(find.byType(DestinationSearchBar), findsNothing);
    });
  });
}
