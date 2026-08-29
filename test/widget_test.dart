import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_auto/main.dart';
import 'package:my_auto/models/nearby_driver_model.dart';
import 'package:my_auto/models/ride_result_model.dart';
import 'package:my_auto/services/geocoding/photon_service.dart';

void main() {
  group('PhotonResult Model Tests', () {
    test('parses backend proxy format correctly', () {
      final json = {
        'name': 'Kollam Junction',
        'display_name': 'Kollam Junction Railway Station, Kollam, Kerala, India',
        'latitude': 8.8872,
        'longitude': 76.5985,
        'city': 'Kollam',
        'state': 'Kerala',
        'country': 'India',
      };

      final result = PhotonResult.fromJson(json);

      expect(result.placeName, 'Kollam Junction');
      expect(result.displayLabel, 'Kollam Junction Railway Station, Kollam, Kerala, India');
      expect(result.latitude, 8.8872);
      expect(result.longitude, 76.5985);
      expect(result.city, 'Kollam');
    });

    test('parses GeoJSON feature format correctly', () {
      final feature = {
        'geometry': {
          'coordinates': [76.6000, 8.9000],
          'type': 'Point',
        },
        'properties': {
          'name': 'Asramam Ground',
          'city': 'Kollam',
          'state': 'Kerala',
          'country': 'India',
        },
      };

      final result = PhotonResult.fromJson(feature);

      expect(result.placeName, 'Asramam Ground');
      expect(result.latitude, 8.9000);
      expect(result.longitude, 76.6000);
      expect(result.displayLabel, contains('Asramam Ground'));
    });
  });

  group('NearbyDriverModel Tests', () {
    test('parses driver response with availability and freshness', () {
      final json = {
        'driver_uid': 'drv_123',
        'latitude': 8.5241,
        'longitude': 76.9366,
        'distance_km': 1.25,
        'freshness': 'LIVE',
        'is_available': true,
        'rating': 4.8,
      };

      final driver = NearbyDriverModel.fromJson(json);

      expect(driver.driverUid, 'drv_123');
      expect(driver.latitude, 8.5241);
      expect(driver.longitude, 76.9366);
      expect(driver.distanceKm, 1.25);
      expect(driver.isAvailable, true);
      expect(driver.isStale, false);
      expect(driver.rating, 4.8);
    });

    test('copyWithPresenceEvent updates location and state', () {
      const initial = NearbyDriverModel(
        driverUid: 'drv_123',
        latitude: 8.5241,
        longitude: 76.9366,
        distanceKm: 1.25,
      );

      final updated = initial.copyWithPresenceEvent({
        'latitude': 8.5300,
        'longitude': 76.9400,
        'freshness': 'LIVE',
        'state': 'CONTACTED',
      });

      expect(updated.latitude, 8.5300);
      expect(updated.longitude, 76.9400);
      expect(updated.isAvailable, false);
    });
  });

  group('RideRequestResult Tests', () {
    test('parses ride response correctly', () {
      final json = {
        'request_id': 'req_abc_999',
        'status': 'matching',
        'message': 'Driver found, waiting for response.',
        'driver_uid': 'drv_123',
      };

      final result = RideRequestResult.fromJson(json);

      expect(result.requestId, 'req_abc_999');
      expect(result.status, 'matching');
      expect(result.isMatching, true);
      expect(result.isExpired, false);
      expect(result.driverUid, 'drv_123');
    });
  });

  group('Widget Tests', () {
    testWidgets('App renders MaterialApp with ProviderScope', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MyAutoApp(),
        ),
      );

      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
