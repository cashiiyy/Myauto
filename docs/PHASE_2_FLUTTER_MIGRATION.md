# MyAuto — Phase 2 Flutter Migration

## Overview

Phase 2 connects the existing Flutter app to the centralized FastAPI + Redis + PostgreSQL backend built in Phase 1. The migration follows the **Backend-Primary** model: all mobility state is owned and authoritative in the backend. Firebase Auth and Firestore profile data are preserved.

---

## Architecture Decision: Backend-Primary (Not Dual-Write)

Per user instruction, the backend is the **sole authority** for:

| Data | Before Phase 2 | After Phase 2 |
|------|---------------|---------------|
| Driver GPS location | Firebase RTDB `active_drivers/` | `POST /api/location` → Redis |
| Nearby drivers (map) | RTDB stream | REST poll + WebSocket events |
| Ride requests | RTDB `ride_requests/` | `POST /api/rides/requests` |
| Ride state (accept/reject) | RTDB | WebSocket events |
| Driver availability | Firestore `users/{uid}.isAvailable` | Redis `driver:availability:{uid}` |

**Preserved** (not migrated):
- Firebase Auth (sign-in, token source)
- Firestore user profiles (`users/{uid}`)
- RTDB ride-share entries (temporary, pending backend endpoint)

---

## New Components

### Flutter

| File | Purpose |
|------|---------|
| `lib/config/app_config.dart` | Backend URL, WS URL, constants via `--dart-define` |
| `lib/services/backend/api_client.dart` | Authenticated Dio HTTP client |
| `lib/services/backend/ws_client.dart` | Persistent WebSocket client |
| `lib/models/backend_event.dart` | Typed WS event envelope |
| `lib/models/nearby_driver_model.dart` | Backend driver response model |
| `lib/models/ride_result_model.dart` | Ride lifecycle result models |
| `lib/providers/backend_client_provider.dart` | API client Riverpod provider |
| `lib/providers/ws_provider.dart` | WS client + event stream providers |
| `lib/providers/backend_drivers_provider.dart` | Backend-sourced driver state |
| `lib/providers/ws_event_router.dart` | Routes WS events to controllers |

### Modified Flutter

| File | Change |
|------|--------|
| `lib/providers/ride_action_provider.dart` | Full backend: bookRide/cancelRide via API |
| `lib/providers/location_provider.dart` | Removed Firestore GPS sync |
| `lib/providers/rtdb_provider.dart` | Deprecated mobility streams annotated |
| `lib/services/driver_location_service.dart` | GPS stream → backend (no RTDB) |
| `lib/screens/home_screen.dart` | Backend driver markers, WS banner, accept/reject UI |

---

## Backend Fixes Applied

| Issue | Fix |
|-------|-----|
| `GET /api/drivers/nearby` returned passenger's own coords | Fetches actual driver coords from Redis hash |
| `POST /api/location` hardcoded role=driver | Accepts role from request body |
| Ride request returned `"temp-uuid-for-now"` | Uses `uuid4()` |
| No cancel/complete/SOS endpoints | Added all three |
| `MatchActionResponse.match_id` UUID type mismatch | Changed to `str` |
| `server_timestamp=0` on error path | Fixed to `datetime.now(UTC)` |
| WebSocket handler handled only pong | Full dispatch: ping, pong, location_update, subscribe_ride |
| Empty test stubs | Real pytest tests with fakeredis + httpx |

---

## Communication Flow (New)

```
Driver GPS
  └─► DriverLocationService.getPositionStream(distanceFilter=5m)
        └─► POST /api/location (Authorization: Bearer <firebase_token>)
              └─► Backend validates → Redis GEOADD + hash + TTL refresh

Passenger opens app
  └─► BackendWebSocketClient.connect(ws://host/ws?token=<token>)
  └─► BackendDriversNotifier.poll() every 5s
        └─► GET /api/drivers/nearby?lat=…&lng=…&radius_km=2.0
              └─► Redis GEOSEARCH → returns actual driver coords
  └─► Driver markers updated on map

Passenger books ride
  └─► POST /api/rides/requests {pickup_lat, pickup_lng}
        └─► Matching engine: Redis GEOSEARCH → Haversine rank → atomic lock
        └─► WebSocket: ride.requested → Driver
        └─► WebSocket: ride.matched → Passenger

Driver receives ride.requested
  └─► incomingRideRequestProvider updated
  └─► Accept/Reject sheet shown
        ├─► Accept: POST /api/matches/{id}/accept
        │     └─► WebSocket: ride.accepted → Passenger
        └─► Reject: POST /api/matches/{id}/reject
              └─► WebSocket: ride.rejected → Passenger

SOS
  └─► Phone dialer (always first)
  └─► POST /api/rides/requests/{id}/sos
        └─► WebSocket: sos.triggered → all ride participants
```

---

## Build Commands

### Development (Tailscale)

```bash
flutter run \
  --dart-define=BACKEND_URL=http://100.89.251.123:8000 \
  --dart-define=BACKEND_WS_URL=ws://100.89.251.123:8000/ws
```

### Mock Mode (no backend needed)

```bash
flutter run --dart-define=MOCK_MODE=true
```

### Production (HTTPS)

```bash
flutter build apk \
  --dart-define=BACKEND_URL=https://api.myauto.app \
  --dart-define=BACKEND_WS_URL=wss://api.myauto.app/ws \
  --dart-define=MOCK_MODE=false
```

---

## Known Limitations

- Background GPS not tested on physical hardware (foreground tracking only)
- Ride share not yet migrated to backend (RTDB writes preserved temporarily)
- PostgreSQL DB writes partially stubbed (ride IDs survive Redis TTL in-session only)
- No masked calling (phone dialer only, within authorized ride context)
- Driver name/vehicle number not returned by `/api/drivers/nearby` (privacy by design)
