/// Result models for the ride lifecycle API.
library;

// ── Ride Request Result ──────────────────────────────────────────────────────

/// Result of POST /api/rides/requests
class RideRequestResult {
  /// Server-assigned UUID for this ride request.
  final String requestId;

  /// 'matching' | 'expired' | 'error'
  final String status;
  final String message;

  /// UID of the matched driver (present when status == 'matching')
  final String? driverUid;

  const RideRequestResult({
    required this.requestId,
    required this.status,
    required this.message,
    this.driverUid,
  });

  bool get isMatching => status == 'matching';
  bool get isExpired => status == 'expired';

  factory RideRequestResult.fromJson(Map<String, dynamic> json) {
    return RideRequestResult(
      requestId: json['request_id'] as String? ?? '',
      status: json['status'] as String? ?? 'error',
      message: json['message'] as String? ?? '',
      driverUid: json['driver_uid'] as String?,
    );
  }

  @override
  String toString() =>
      'RideRequestResult(id=$requestId, status=$status, driver=$driverUid)';
}

// ── Match Action Result ───────────────────────────────────────────────────────

/// Result of POST /api/matches/{id}/accept or /reject
class MatchActionResult {
  final String matchId;

  /// 'accepted' | 'rejected'
  final String status;
  final String message;

  const MatchActionResult({
    required this.matchId,
    required this.status,
    required this.message,
  });

  bool get isAccepted => status == 'accepted';

  factory MatchActionResult.fromJson(Map<String, dynamic> json) {
    return MatchActionResult(
      matchId: json['match_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

// ── SOS Result ───────────────────────────────────────────────────────────────

/// Result of POST /api/rides/{id}/sos
class SosResult {
  final String sosEventId;
  final bool acknowledged;
  final String message;

  const SosResult({
    required this.sosEventId,
    required this.acknowledged,
    required this.message,
  });

  factory SosResult.fromJson(Map<String, dynamic> json) {
    return SosResult(
      sosEventId: json['sos_event_id'] as String? ?? '',
      acknowledged: json['acknowledged'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}
