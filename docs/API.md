# MyAuto API Reference

Base URL: `http://100.89.251.123:8000` (Tailscale dev)
All endpoints require `Authorization: Bearer <firebase_id_token>` except `/health`.

---

## Health

### `GET /health`
**No auth required.**
```json
{ "status": "ok" }
```

---

## Location

### `POST /api/location`
Send a GPS update.

**Body:**
```json
{
  "latitude": 8.5241,
  "longitude": 76.9366,
  "accuracy_meters": 10.0,
  "speed_mps": 5.0,
  "heading_degrees": 90.0,
  "altitude": 5.0,
  "captured_at": 1724350800000,
  "sequence": 42,
  "role": "driver"
}
```

- `role`: `"driver"` | `"passenger"`
- `captured_at`: Unix epoch milliseconds (device time — used for freshness only, not as authority)
- `sequence`: monotonically increasing integer (server rejects out-of-order updates)

**Response `200`:**
```json
{
  "accepted": true,
  "freshness": "LIVE",
  "server_timestamp": "2024-08-22T10:30:00.000Z",
  "message": "Location updated"
}
```

**Freshness values:** `LIVE` (≤5s old) | `DELAYED` (≤15s) | `STALE` (≤30s) | `OFFLINE` (rejected)

---

## Drivers

### `GET /api/drivers/nearby`
Returns nearby available drivers.

**Query params:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `lat` | float | required | Passenger latitude |
| `lng` | float | required | Passenger longitude |
| `radius_km` | float | 2.0 | Search radius |

**Response `200` — array of:**
```json
{
  "driver_uid": "abc123",
  "latitude": 8.5260,
  "longitude": 76.9380,
  "distance_km": 0.42,
  "heading_degrees": 45.0,
  "accuracy_meters": 10.0,
  "freshness": "LIVE",
  "vehicle_type": "auto-rickshaw",
  "is_available": true
}
```

> **Privacy:** Phone number, name, vehicle registration are NEVER returned by this endpoint.

---

## Rides

### `POST /api/rides/requests`
Passenger creates a ride request. Server finds and atomically reserves nearest driver.

**Body:**
```json
{
  "pickup_lat": 8.5241,
  "pickup_lng": 76.9366,
  "pickup_accuracy_meters": 15.0,
  "notes": "Near the petrol station"
}
```

**Response `200` — matching found:**
```json
{
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "matching",
  "message": "Match found, waiting for driver response.",
  "created_at": "2024-08-22T10:30:00.000Z"
}
```

**Response `200` — no drivers:**
```json
{
  "request_id": "550e8400-e29b-41d4-a716-446655440001",
  "status": "expired",
  "message": "No eligible drivers found nearby.",
  "created_at": "2024-08-22T10:30:01.000Z"
}
```

---

### `POST /api/rides/requests/{ride_id}/cancel`
Cancel a pending or active ride. Only the passenger who created it may cancel.

**Response `200`:**
```json
{ "ride_id": "550e8400...", "status": "cancelled", "message": "Ride cancelled." }
```

---

### `POST /api/rides/requests/{ride_id}/complete`
Mark a ride as completed. Only the driver or passenger in the ride may call this.

**Response `200`:**
```json
{ "ride_id": "550e8400...", "status": "completed", "message": "Ride completed." }
```

---

### `POST /api/rides/requests/{ride_id}/sos`
Trigger an SOS alert. Sends WebSocket `sos.triggered` to all ride participants.

**Body (all optional):**
```json
{
  "latitude": 8.5241,
  "longitude": 76.9366,
  "message": "Need help!"
}
```

**Response `200`:**
```json
{
  "sos_event_id": "uuid",
  "acknowledged": true,
  "message": "SOS received. Emergency contacts notified."
}
```

---

## Matches

### `POST /api/matches/{match_id}/accept`
Driver accepts a matched ride request.

**Response `200`:**
```json
{
  "match_id": "550e8400...",
  "status": "accepted",
  "message": "Match accepted. Your ride is confirmed."
}
```

---

### `POST /api/matches/{match_id}/reject`
Driver rejects a match. Driver is returned to AVAILABLE. Server re-attempts matching.

**Response `200`:**
```json
{
  "match_id": "550e8400...",
  "status": "rejected",
  "message": "Match rejected. Looking for next available driver."
}
```

---

## Error Responses

| Code | Meaning |
|------|---------|
| `401` | Missing or invalid Firebase ID token |
| `403` | Authenticated but not authorized (wrong role or not in ride) |
| `422` | Request body validation failed |
| `500` | Internal server error |

Error body:
```json
{ "detail": "Human-readable error message" }
```
