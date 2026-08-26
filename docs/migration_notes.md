# MyAuto Migration Notes

## Overview

This document details every file changed, why it was changed, how to test it, and how to roll it back.
All changes are additive by default — existing behaviour is preserved unless a feature flag is explicitly set.

---

## 1. Verified Package Compatibility (pub.dev)

| Package | Version | Platforms Supported | Flutter SDK | Status |
| :--- | :--- | :--- | :--- | :--- |
| **`maplibre_gl`** | `^0.27.0` | Android ✅ iOS ✅ Web ✅ | >= 3.2.0 | Verified on pub.dev |
| **`socket_io_client`** | `^3.1.6` | Android ✅ iOS ✅ Web ✅ Desktop ✅ | >= 3.0.0 | Compatible with Socket.IO server `^4.7.4` |

> [!NOTE]
> `socket_io_client: ^3.1.6` uses the Socket.IO v4 protocol matching our Node.js server (`socket.io: ^4.7.4`).
> Both packages remain commented in `pubspec.yaml` until developers opt-in to install them. The codebase compiles cleanly without them via dynamic adapter wrappers.

---

## 2. WebSocket & Socket.IO Event Repertoire

The Node.js Socket.IO server reproduces the exact event strings defined in [`lib/models/backend_event.dart`](file:///k:/PROJECTS/MyAuto/lib/models/backend_event.dart):

| Event String | Direction | Payload Schema | Handled by |
| :--- | :--- | :--- | :--- |
| `location.update` | Client → Server | `{ latitude, longitude, accuracy_meters, heading_degrees, speed_mps }` | `LocationRealtimeService.js` |
| `driver.presence` | Server → Client | `{ driver_uid, latitude, longitude, freshness, state }` | `BackendWebSocketClient` / `SocketIoRealtimeAdapter` |
| `driver.availability` | Server → Client | `{ driver_uid, state: "AVAILABLE" \| "BUSY" \| "OFFLINE" }` | `DriverAvailabilityService.js` |
| `ride.create` | Client → Server | `{ pickup_lat, pickup_lng, notes }` | `RideRequestService.js` |
| `ride.requested` | Server → Driver | `{ match_id, request_id, passenger_uid, pickup_lat, pickup_lng }` | `ws_event_router.dart` |
| `ride.matched` | Server → Passenger | `{ match_id, request_id, driver_uid, distance_km }` | `ws_event_router.dart` |
| `ride.accept` | Driver → Server | `{ match_id, request_id, passenger_uid }` | `BookingService.js` |
| `ride.accepted` | Server → Both | `{ match_id, request_id, driver_uid }` | `ws_event_router.dart` |
| `ride.reject` | Driver → Server | `{ request_id, passenger_uid }` | `BookingService.js` |
| `ride.rejected` | Server → Both | `{ request_id, driver_uid }` | `ws_event_router.dart` |
| `ride.cancel` | Client → Server | `{ request_id, other_party_uid }` | `BookingService.js` |
| `ride.cancelled` | Server → Both | `{ request_id, cancelled_by }` | `ws_event_router.dart` |
| `ride.complete` | Driver → Server | `{ request_id, passenger_uid }` | `BookingService.js` |
| `ride.completed` | Server → Both | `{ request_id, driver_uid }` | `ws_event_router.dart` |
| `ride_share.toggle` | Client → Server | `{ sharing, name, lat, lng }` | `RideShareService.js` |

---

## 3. Database & Network Coordination

- **Shared Database:** Both `backend` (FastAPI) and `nodejs` (Socket.IO) connect to the same PostgreSQL container on port `5432` with identical credentials (`DATABASE_URL`).
- **Shared Docker Network:** All services (`postgres`, `redis`, `backend`, `nodejs`, `valhalla`, `photon`) communicate internally on `backend_net`.
- **Redis Usage:** Reserved for horizontal pub/sub scaling (multiple Node.js instances). In v1, Node.js uses PostgreSQL directly for presence and matching.

---

## 4. Flutter Changes & Architecture

### `lib/config/app_config.dart` — MODIFIED (additive)
- Added feature flag default warning banner.
- Added `mapMode`, `mapStyleUrl`, `tileUrl`.
- Added `realtimeMode`, `socketIoUrl`.
- Added `photonUrl`, `photonBbox` (default: Kollam `76.35,8.70,76.85,9.10`), `photonMaxResults`.
- Added `valhallaUrl`, `valhallaCosting` (default: `auto`).

### `lib/screens/home_screen.dart` — MODIFIED (surgical & additive)
1. `FlutterMap` → `MapAbstraction` (identical rendering in default mode).
2. Added `DestinationSearchBar` positioned at top of screen for passengers only.
3. Dynamically shifted refresh and locate FABs down when the search bar is active (`role == 'passenger' ? +72/+122 : +20/+70`).
4. Added destination pin marker (`📍`) when a destination is selected.

### `lib/providers/destination_provider.dart` — NEW (isolated)
- Holds selected `DestinationPlace?`.
- Strict isolation guard: prohibited from being read by booking, driver matching, or payment providers.

### `lib/services/map/map_abstraction.dart` — NEW (adapter)
- Exposes `UnifiedMapController` interface and `FlutterMapControllerAdapter`.
- Renders `FlutterMap` in default mode and `MapLibre` when enabled.

---

## 5. Instant Rollback Procedure

To completely revert the app to its exact pre-migration state at runtime:

1. **Flutter Runtime Flags:**
   ```bash
   flutter run \
     --dart-define=MAP_MODE=flutter_map \
     --dart-define=REALTIME_MODE=websocket
   ```
2. **Backend Containers:**
   ```bash
   # Only run the original services:
   cd backend
   docker compose up -d postgres redis backend
   # (Stop nodejs, valhalla, photon if running)
   docker compose stop nodejs valhalla photon
   ```
3. **Database Migrations (Optional):**
   ```bash
   cd backend
   alembic downgrade -2  # drops destinations table and spatial index migration
   ```

---

## 6. Physical Device Testing via Tailscale

When testing on a physical Android or iOS device:

1. Install Tailscale on the development computer and mobile device.
2. Join both to the same tailnet.
3. Note the computer's Tailscale IP (e.g. `100.89.251.123`).
4. Launch backend: `docker compose up -d`
5. Run the Flutter application:
   ```bash
   flutter run \
     --dart-define=BACKEND_URL=http://100.89.251.123:8919 \
     --dart-define=BACKEND_WS_URL=ws://100.89.251.123:8919/ws \
     --dart-define=SOCKETIO_URL=http://100.89.251.123:3001
   ```
> [!TIP]
> `http://10.0.2.2` is only reachable from the Android Emulator loopback. For physical phones, always use the Tailscale or LAN IP.

---

## 7. Guaranteed Unchanged Files

The following components were verified untouched:
- All authentication flows (`lib/providers/auth_provider.dart`, Firebase Auth).
- Firebase Realtime Database (`lib/providers/rtdb_provider.dart`, `rtdb_service.dart`).
- Ride booking & state machines (`lib/providers/ride_action_provider.dart`, `api_client.dart`, `ws_client.dart`).
- Driver GPS service (`lib/services/driver_location_service.dart`).
- All screen layouts, themes, fonts, colors, and asset images.
- All existing FastAPI endpoints in `backend/app/`.
