import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_auto/features/map/services/marker_service.dart';
import 'package:my_auto/models/user_model.dart';
import 'package:my_auto/providers/auth_provider.dart';
import 'package:my_auto/providers/backend_drivers_provider.dart';
import 'package:my_auto/providers/location_provider.dart';
import 'package:my_auto/providers/backend_client_provider.dart';
import 'package:my_auto/providers/ws_provider.dart';
import 'package:my_auto/services/backend/api_client.dart';
import 'package:my_auto/screens/home_screen.dart';
import 'package:my_auto/widgets/destination_search_bar.dart';

class MockBackendApiClient extends BackendApiClient {
  MockBackendApiClient() : super(auth: null);
}

class MockBackendWebSocketClient extends BackendWebSocketClient {
  MockBackendWebSocketClient() : super(auth: null);
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
}

class FakeBackendDriversNotifier extends StateNotifier<BackendDriversState> implements BackendDriversNotifier {
  FakeBackendDriversNotifier() : super(const BackendDriversState());

  @override
  Future<void> refresh() async {}
}

void main() {
  group('HomeScreen Widget Tests', () {
    testWidgets('Passenger role shows DestinationSearchBar', (WidgetTester tester) async {
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
            wsConnectionStateProvider.overrideWith((ref) => Stream.value(WsConnectionState.connected)),
            backendDriversProvider.overrideWith((ref) => FakeBackendDriversNotifier()),
            markerServiceProvider.overrideWith((ref) => Future.value(MarkerService())),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      // Location loading overlay assertion
      expect(find.text('Acquiring GPS location...'), findsOneWidget);

      // DestinationSearchBar visible for passenger
      expect(find.byType(DestinationSearchBar), findsOneWidget);
    });

    testWidgets('Driver role hides DestinationSearchBar', (WidgetTester tester) async {
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
            wsConnectionStateProvider.overrideWith((ref) => Stream.value(WsConnectionState.connected)),
            backendDriversProvider.overrideWith((ref) => FakeBackendDriversNotifier()),
            markerServiceProvider.overrideWith((ref) => Future.value(MarkerService())),
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
