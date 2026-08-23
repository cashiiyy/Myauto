/// Typed model for WebSocket events received from the MyAuto backend.
///
/// Every event carries:
/// - [eventId]        — UUID for deduplication (ignore duplicate eventIds)
/// - [type]           — one of the [BackendEventType] values
/// - [serverTimestamp]— ISO-8601 UTC time the event was created on the server
/// - [rideId]         — present on ride lifecycle events
/// - [payload]        — event-specific data (driver uid, coordinates, etc.)
library;

/// Canonical event type values as sent by the backend.
enum BackendEventType {
  locationUpdate('location.update'),
  driverPresence('driver.presence'),
  driverAvailability('driver.availability'),
  rideRequested('ride.requested'),   // driver receives this
  rideMatched('ride.matched'),       // passenger receives this
  rideAccepted('ride.accepted'),
  rideRejected('ride.rejected'),
  rideCancelled('ride.cancelled'),
  rideCompleted('ride.completed'),
  sosTriggered('sos.triggered'),
  heartbeat('heartbeat'),
  error('error'),
  unknown('unknown');

  const BackendEventType(this.value);
  final String value;

  static BackendEventType fromString(String s) {
    for (final t in BackendEventType.values) {
      if (t.value == s) return t;
    }
    return BackendEventType.unknown;
  }
}

/// Envelope for every WebSocket event sent by the backend.
class BackendEvent {
  final String eventId;
  final BackendEventType type;
  final String serverTimestamp;
  final String? rideId;
  final Map<String, dynamic> payload;

  const BackendEvent({
    required this.eventId,
    required this.type,
    required this.serverTimestamp,
    this.rideId,
    this.payload = const {},
  });

  factory BackendEvent.fromJson(Map<String, dynamic> json) {
    return BackendEvent(
      eventId: json['event_id'] as String? ?? '',
      type: BackendEventType.fromString(json['type'] as String? ?? ''),
      serverTimestamp: json['server_timestamp'] as String? ?? '',
      rideId: json['ride_id'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  String toString() =>
      'BackendEvent(type=${type.value}, ride=$rideId, id=$eventId)';
}
