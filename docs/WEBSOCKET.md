# WebSocket Protocol

The MyAuto WebSocket API is used for real-time, low-latency, bidirectional communication between the app and the backend.

**Endpoint:** `ws://<host>/ws?token=<firebase_id_token>`

Authentication is enforced on connection. If the token expires during a long-lived connection, the client will eventually be disconnected and must fetch a new token to reconnect.

## Message Envelope

All outbound events from the server follow this JSON schema:

```json
{
  "event_id": "c1f7b7ce-...",
  "type": "event.name",
  "server_timestamp": "2024-08-22T10:30:00Z",
  "ride_id": "optional-ride-uuid",
  "payload": { ... }
}
```

## Server → Client Events

| Type | Recipient | Payload | Purpose |
|------|-----------|---------|---------|
| `heartbeat` | All | None | Sent every 20s. Client must reply with `pong` to keep connection alive. |
| `ride.requested` | Driver | `pickup_lat`, `pickup_lng`, `passenger_uid`, `match_id` | Match found. Show Accept/Reject sheet. |
| `ride.matched` | Passenger | `driver_uid`, `match_id` | Match found. Driver is being notified. |
| `ride.accepted` | Passenger | `driver_uid` | Driver accepted the ride. |
| `ride.rejected` | Passenger | `message` | Driver rejected. Passenger UI goes back to finding state. |
| `ride.cancelled` | Both | `message` | Ride was cancelled. |
| `ride.completed` | Both | `message` | Ride finished successfully. |
| `sos.triggered` | Both | `message` | Someone pressed the SOS button. |
| `error` | Any | `message` | Server-side validation error on a WS action. |

## Client → Server Messages

Client can send lightweight JSON messages without HTTP overhead.

```json
{
  "type": "pong",
  "payload": {}
}
```

| Type | Payload | Purpose |
|------|---------|---------|
| `ping` | None | Client-initiated keepalive (optional, server sends heartbeats anyway) |
| `pong` | None | Reply to server `heartbeat` |
| `subscribe_ride` | `{"ride_id": "uuid"}` | Join a ride session room to receive targeted events. |
| `unsubscribe_ride`| `{"ride_id": "uuid"}` | Leave a ride session room. |
