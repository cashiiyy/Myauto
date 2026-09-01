import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:my_auto/features/map/presentation/widgets/map_controls_overlay.dart';
import 'package:my_auto/features/map/providers/map_controller_provider.dart';
import 'package:my_auto/features/map/services/marker_service.dart';
import 'package:my_auto/models/auto_model.dart';
import 'package:my_auto/models/nearby_driver_model.dart';
import 'package:my_auto/providers/backend_client_provider.dart';
import 'package:my_auto/providers/backend_drivers_provider.dart';
import 'package:my_auto/providers/destination_provider.dart';
import 'package:my_auto/providers/location_provider.dart';
import 'package:my_auto/providers/ride_action_provider.dart';
import 'package:my_auto/providers/selected_driver_provider.dart';
import 'package:my_auto/services/backend/api_client.dart';
import 'package:my_auto/widgets/auto_details_sheet.dart';

class MockBackendApiClient extends BackendApiClient {
  MockBackendApiClient() : super(auth: null);
}

class FakeBackendDriversNotifier extends StateNotifier<BackendDriversState>
    implements BackendDriversNotifier {
  bool refreshCalled = false;
  FakeBackendDriversNotifier([List<NearbyDriverModel> drivers = const []])
      : super(BackendDriversState(drivers: drivers));

  @override
  Future<void> refresh() async {
    refreshCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkerService Tests', () {
    late MarkerService markerService;

    setUp(() async {
      markerService = MarkerService();
      await markerService.initialize();
    });

    test('initializes and caches vector marker descriptors', () {
      expect(markerService.isInitialized, true);
    });

    test('builds accurate markers for nearby drivers in passenger mode', () {
      final drivers = [
        const NearbyDriverModel(
          driverUid: 'drv_1',
          latitude: 8.5241,
          longitude: 76.9366,
          distanceKm: 0.45,
          isAvailable: true,
          freshness: 'LIVE',
          rating: 4.9,
        ),
        const NearbyDriverModel(
          driverUid: 'drv_2',
          latitude: 8.5300,
          longitude: 76.9400,
          distanceKm: 1.10,
          isAvailable: false,
          freshness: 'LIVE',
          rating: 4.5,
        ),
      ];

      final markers = markerService.buildMarkers(
        drivers: drivers,
        currentPosition: Position(
          longitude: 76.9366,
          latitude: 8.5241,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        ),
        destination: null,
        rideShares: const [],
        incomingRequest: null,
        selectedDriverUid: 'drv_1',
        userRole: 'passenger',
      );

      // Should have: user location marker + 2 driver markers = 3 markers
      expect(markers.length, 3);

      final driver1Marker = markers.firstWhere((m) => m.markerId.value == 'driver_drv_1');
      expect(driver1Marker.position.latitude, 8.5241);
      expect(driver1Marker.position.longitude, 76.9366);
      expect(driver1Marker.zIndexInt, 3); // selected driver gets elevated zIndex

      final driver2Marker = markers.firstWhere((m) => m.markerId.value == 'driver_drv_2');
      expect(driver2Marker.position.latitude, 8.5300);
      expect(driver2Marker.position.longitude, 76.9400);
      expect(driver2Marker.zIndexInt, 2);
    });

    test('filters out stale drivers automatically', () {
      final drivers = [
        const NearbyDriverModel(
          driverUid: 'drv_stale',
          latitude: 8.5241,
          longitude: 76.9366,
          distanceKm: 0.5,
          freshness: 'OFFLINE',
          isAvailable: true,
        ),
      ];

      final markers = markerService.buildMarkers(
        drivers: drivers,
        currentPosition: null,
        destination: null,
        rideShares: const [],
        incomingRequest: null,
        selectedDriverUid: null,
        userRole: 'passenger',
      );

      expect(markers.isEmpty, true);
    });
  });

  group('MapControlsOverlay Widget Tests', () {
    testWidgets('renders all map controls (scan, recenter, location, diag, sos)',
        (WidgetTester tester) async {
      bool diagOpened = false;
      bool sosTriggered = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentLocationProvider.overrideWith((ref) => Stream.value(
                  Position(
                    longitude: 76.9366,
                    latitude: 8.5241,
                    timestamp: DateTime.now(),
                    accuracy: 5.0,
                    altitude: 0.0,
                    altitudeAccuracy: 0.0,
                    heading: 0.0,
                    headingAccuracy: 0.0,
                    speed: 0.0,
                    speedAccuracy: 0.0,
                  ),
                )),
            backendDriversProvider.overrideWith((ref) => FakeBackendDriversNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MapControlsOverlay(
                role: 'passenger',
                onOpenDiagnostics: () => diagOpened = true,
                onTriggerSos: () => sosTriggered = true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('discovery_scan_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('recenter_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('my_location_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('diag_btn')), findsOneWidget);
      expect(find.text('SOS'), findsOneWidget);

      // Tap diagnostics button
      await tester.tap(find.byKey(const ValueKey('diag_btn')));
      expect(diagOpened, true);

      // Tap SOS button
      await tester.tap(find.text('SOS'));
      expect(sosTriggered, true);
    });

    testWidgets('discovery scan button triggers refresh on notifier',
        (WidgetTester tester) async {
      final fakeNotifier = FakeBackendDriversNotifier([
        const NearbyDriverModel(
          driverUid: 'drv_test_1',
          latitude: 8.5241,
          longitude: 76.9366,
          distanceKm: 0.5,
          isAvailable: true,
          freshness: 'LIVE',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentLocationProvider.overrideWith((ref) => const Stream.empty()),
            backendDriversProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MapControlsOverlay(
                role: 'passenger',
                onOpenDiagnostics: () {},
                onTriggerSos: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Tap scan button
      await tester.tap(find.byKey(const ValueKey('discovery_scan_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakeNotifier.refreshCalled, true);
    });
  });

  group('AutoDetailsSheet Widget Tests', () {
    testWidgets('displays auto details and handles available booking',
        (WidgetTester tester) async {
      final auto = AutoModel(
        id: 'drv_999',
        latitude: 8.5241,
        longitude: 76.9366,
        isAvailable: true,
        driverName: 'Ramesh Kumar',
        phoneNumber: '+919876543210',
        vehicleNumber: 'KL-01-CB-4040',
        rating: 4.9,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendApiClientProvider.overrideWithValue(MockBackendApiClient()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AutoDetailsSheet(
                auto: auto,
                distance: 1.2,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Ramesh Kumar'), findsOneWidget);
      expect(find.text('KL-01-CB-4040'), findsOneWidget);
      expect(find.text('AVAILABLE'), findsOneWidget);
      expect(find.text('Request This Auto'), findsOneWidget);
      expect(find.text('1.2 km'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
    });

    testWidgets('displays busy status and disables booking when unavailable',
        (WidgetTester tester) async {
      final auto = AutoModel(
        id: 'drv_busy',
        latitude: 8.5241,
        longitude: 76.9366,
        isAvailable: false,
        driverName: 'Suresh Nair',
        phoneNumber: '',
        vehicleNumber: 'KL-01-AB-1234',
        rating: 4.7,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendApiClientProvider.overrideWithValue(MockBackendApiClient()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AutoDetailsSheet(
                auto: auto,
                distance: 2.5,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('BUSY'), findsOneWidget);
      expect(find.text('Auto Unavailable'), findsOneWidget);

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull); // disabled
    });
  });
}
