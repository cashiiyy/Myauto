# MyAuto — Phase 1 Architecture Impact Report

> **Status**: Phase 1 — Backend Build (Flutter untouched)
> **Date**: 2026-08-22
> **Project**: `myauto-dd21e` (Firebase)

---

## 1. Current Architecture

### Overview

MyAuto is a Flutter application using a **fully client-centric, P2P-style real-time architecture**. There is no centralized application server. All geospatial computation, proximity filtering, and state management happens on each client device.

### Components

| Component | Technology | Role |
|-----------|-----------|------|
| Mobile App | Flutter / Dart | UI + all business logic |
| State Management | Riverpod (StateNotifier, StreamProvider) | Reactive app state |
| Identity | Firebase Authentication | Email/password + Google Sign-In |
| User Profiles | Cloud Firestore | Durable user data, role, vehicle info |
| Live Tracking | Firebase Realtime Database (RTDB) | Live GPS coordinates |
| Maps | flutter_map + OpenStreetMap | Map display |
| GPS | geolocator + permission_handler | Device GPS access |
| Proximity | Haversine (Dart, client-side) | Distance calculations |

### RTDB Node Structure

```
Firebase RTDB (asia-southeast1)
├── active_drivers/
│   └── {uid}/
│       ├── uid
│       ├── name
│       ├── phone          ← EXPOSED to all authenticated users
│       ├── vehicleNumber
│       ├── latitude
│       ├── longitude
│       ├── heading
│       ├── isAvailable
│       ├── rating
│       └── updatedAt      ← Unix ms, written by client
├── ride_requests/
│   └── {uid}/
│       ├── uid
│       ├── name
│       ├── phone          ← EXPOSED to all authenticated users
│       ├── latitude
│       ├── longitude
│       ├── status         ← 'waiting' | 'accepted' | 'cancelled' (string, no machine)
│       └── createdAt
└── ride_shares/
    └── {uid}/
        ├── uid
        ├── name
        ├── phone          ← EXPOSED to all authenticated users
        ├── latitude / longitude
        ├── destLatitude / destLongitude
        ├── seatsAvailable
        └── createdAt
```

### Firestore Collections

```
Firestore
└── users/{uid}
    ├── uid, email, role (passenger|driver)
    ├── name, phone
    ├── isVerified, isRequesting
    ├── latitude, longitude     ← Written by location_provider.dart as side-effect
    ├── autoRegistrationNumber, licenseNumber
    └── driverPhotoUrl, autoPhotoUrl
```

### Key Source Files

| Purpose | File |
|---------|------|
| Flutter entry | `lib/main.dart` |
| Firebase init | `lib/firebase_options.dart` |
| Auth (Riverpod) | `lib/providers/auth_provider.dart` |
| RTDB I/O service | `lib/services/rtdb_service.dart` |
| RTDB providers | `lib/providers/rtdb_provider.dart` |
| Driver GPS push | `lib/services/driver_location_service.dart` |
| Passenger GPS | `lib/providers/location_provider.dart` |
| Location service | `lib/services/location_service.dart` |
| Ride actions | `lib/providers/ride_action_provider.dart` |
| Auto provider | `lib/providers/auto_provider.dart` |
| User model | `lib/models/user_model.dart` |
| Driver loc model | `lib/models/driver_location_model.dart` |
| Ride request model | `lib/models/ride_request_model.dart` |
| Ride share model | `lib/models/ride_share_model.dart` |
| Home screen (map) | `lib/screens/home_screen.dart` |
| SOS screen | `lib/screens/safety_contacts_screen.dart` |
| Mock auto gen | `lib/services/auto_service.dart` |
| Android perms | `android/app/src/main/AndroidManifest.xml` |
| RTDB rules | `database.rules.json` |
| Firestore rules | `firestore.rules` |

---

## 2. Current Data Flow

### Driver GPS Broadcast

```
Driver Flutter App
  │
  ├─ HomeScreen.initState()
  │     └─ _manageDriverService(user)
  │           └─ DriverLocationService.start()
  │                 ├─ rtdb.registerDriverOnDisconnect(uid)   ← onDisconnect hook
  │                 └─ Timer(every 5s) → _pushLocation()
  │                       ├─ Geolocator.getCurrentPosition()
  │                       └─ RtdbService.updateDriverLocation(model)
  │                             └─ FirebaseDatabase.ref('active_drivers/{uid}').set(model)
  │
  └─ On stop/logout: RtdbService.removeDriver(uid)
```

### Passenger Discovery (Client-Side Proximity)

```
Passenger Flutter App
  │
  ├─ nearbyDriversStreamProvider
  │     └─ RtdbService.nearbyDriversStream(centerLat, centerLng, radius=2km)
  │           └─ db.ref('active_drivers').onValue  ← ENTIRE node streamed to client
  │                 └─ For each entry: _haversineKm(center, driver)
  │                       └─ if dist <= 2km: include in result
  │                             └─ MarkerLayer → 🛺 on map
  │
  └─ On marker tap → AutoDetailsSheet → shows driver phone number
```

### Passenger Booking

```
Passenger Flutter
  └─ Book Ride button → rideActionController.bookRide()
        └─ RtdbService.pushRideRequest(RideRequestModel)
              └─ db.ref('ride_requests/{uid}').set(model)
                    └─ Driver's nearbyRideRequestsStreamProvider picks up
                          └─ Client-side Haversine filter (3km)
                                └─ 🧍 marker on driver's map
                                      └─ Driver taps → sees passenger phone
                                            └─ Driver calls passenger directly
```

### Driver Discovery (Client-Side, from Driver POV)

```
Driver Flutter App
  │
  └─ nearbyRideRequestsStreamProvider
        └─ RtdbService.nearbyRideRequestsStream(centerLat, centerLng, radius=3km)
              └─ db.ref('ride_requests').onValue  ← ENTIRE node streamed to driver
                    └─ Filter: status == 'waiting' AND dist <= 3km
                          └─ MarkerLayer → 🧍 on driver's map
```

### SOS Flow (Current)

```
User presses SOS FAB
  └─ _callSos()
        └─ sosContactProvider (default: '100')
              └─ url_launcher → tel:{number}
                    └─ OS phone dialer
                          [NO server event, NO audit trail]
```

---

## 3. Architecture Problems Identified

### Security
- **Phone number exposure**: All authenticated users can read any driver's or passenger's phone number from RTDB (`active_drivers`, `ride_requests`, `ride_shares` nodes)
- **No server authority**: RTDB rules only check `auth.uid === $uid` — the client decides what data to write (isAvailable, isVerified, role)
- **Client controls nearest-driver selection**: A modified client could select any driver regardless of distance
- **No ride ownership**: Any authenticated user can read all ride requests

### Reliability
- **No atomic reservation**: Two passengers can simultaneously write acceptance for the same driver
- **No driver state machine**: Status is a raw string in RTDB with no transition validation
- **Stale locations persist**: If onDisconnect fails (app crash, network loss), stale driver entries remain in RTDB for up to 60s (Firebase persistence window)
- **No sequence tracking**: Old GPS updates can arrive after newer ones (out-of-order pushes)

### Scalability
- **Full RTDB node broadcast**: Every `active_drivers` change triggers a re-delivery of the **entire node** to all connected passengers
- **Client-side computation**: Every Flutter client runs Haversine for every driver on every RTDB update
- **No Redis/in-memory layer**: No fast live state; all reads go to Firebase

### Privacy
- **GPS coordinates in RTDB**: Exact lat/lng of all active drivers and requesting passengers is visible to any authenticated user
- **No contact authorization**: Direct phone-to-phone calls with no anonymization layer

---

## 4. Target Architecture (Phase 1 — Backend)

```
                         Ubuntu Server
                              │
                    ┌─────────┴─────────┐
                    │                   │
                 FastAPI             WebSocket
                (port 8000)           Gateway
                    │                   │
            ┌───────┴────────────┬──────┘
            │                   │
         REST API          Event Bus
            │                   │
        ┌───┴────────────────────┘
        │
 ┌──────┼──────────────────────────────┐
 │      │                              │
 │  Auth Layer          Services       │
 │  (Firebase           ├── Location   │
 │   Admin SDK)         ├── Matching   │
 │      │               ├── Rides      │
 │      │               ├── SOS        │
 │      │               └── Contact    │
 └──────┼──────────────────────────────┘
        │
  ┌─────┴──────┐
  │            │
Redis      PostgreSQL
(live)     + PostGIS
           (durable)
```

### Redis Schema

```
driver:presence:{driverId}     → hash {state, lastSeen, connectionId}  TTL=35s
driver:location:{driverId}     → hash {lat, lng, accuracy, speed, heading, seq, receivedAt}  TTL=30s
driver:availability:{driverId} → string {state}  TTL=35s
passenger:location:{passengerId} → hash {lat, lng, accuracy, capturedAt}  TTL=60s
ride:session:{rideId}          → hash {driverId, passengerId, state, createdAt}  TTL=3600s
ride:rejected:{rideId}         → set of driverIds that rejected  TTL=600s
lock:driver:{driverId}         → string {passengerId}  TTL=10s (atomic reservation)
drivers:geo                    → Redis GEO sorted set (all active drivers)
ws:connections:{uid}           → hash {connectionId, role, lastHeartbeat}
```

### PostgreSQL Schema (PostGIS)

```sql
-- Users and roles
users (id UUID PK, firebase_uid UNIQUE, email, role ENUM, created_at, updated_at)
drivers (id UUID PK, user_id FK, is_verified, verification_status, rating)
driver_verification (id UUID PK, driver_id FK, license_number, vehicle_reg, photo_url, submitted_at, reviewed_at)
vehicles (id UUID PK, driver_id FK, registration, make, model, color)

-- Rides
ride_requests (id UUID PK, passenger_id FK, pickup_location GEOMETRY(Point,4326), status ENUM, created_at, expires_at)
ride_matches (id UUID PK, request_id FK, driver_id FK, passenger_id FK, status ENUM, distance_meters, created_at)
ride_sessions (id UUID PK, match_id FK, driver_id FK, passenger_id FK, state ENUM, started_at, completed_at)
ride_events (id UUID PK, session_id FK, actor_id FK, event_type, payload JSONB, created_at)

-- Audit
audit_events (id UUID PK, actor_id FK, action, entity_type, entity_id UUID, ip_address, payload JSONB, created_at)
```

### New Target Data Flow

```
Driver Flutter
  │
  │ POST /api/location  {lat, lng, accuracy, speed, heading, capturedAt, sequence}
  │ Header: Authorization: Bearer <Firebase ID Token>
  ▼
FastAPI /api/location
  │
  ├─ firebase_auth.verify_token(token) → uid
  ├─ validate_location(payload) — bounds, accuracy, timestamp, speed, heading, sequence
  ├─ freshness_check() → LIVE | DELAYED | STALE
  ├─ Redis: SET driver:location:{uid} HASH
  ├─ Redis: GEOADD drivers:geo lng lat uid
  ├─ Redis: SET driver:presence:{uid} + TTL
  └─ WebSocket: broadcast driver.presence event to subscribed passengers
```

```
Passenger Flutter
  │
  │ POST /api/ride-requests  {pickupLat, pickupLng, accuracy}
  │ Header: Authorization: Bearer <Firebase ID Token>
  ▼
FastAPI /api/ride-requests
  │
  ├─ verify_token → passenger_uid
  ├─ validate_location(pickup)
  ├─ Redis GEORADIUS drivers:geo INITIAL_RADIUS (2km)
  │     → candidates list
  ├─ filter_candidates(candidates)
  │     ├─ state == AVAILABLE
  │     ├─ location freshness == LIVE or DELAYED
  │     ├─ accuracy <= MAX_MATCH_ACCURACY_METERS
  │     ├─ not in ride:rejected:{rideId}
  │     └─ driver not blocked
  ├─ Haversine rank (distance dominant)
  ├─ FOR best_candidate:
  │     ├─ SETNX lock:driver:{driverId} passengerId EX 10
  │     ├─ if lock acquired:
  │     │     ├─ re-check eligibility (double-check)
  │     │     ├─ DB: INSERT ride_requests, ride_matches
  │     │     ├─ Redis: SET driver:availability:{uid} RESERVED
  │     │     ├─ WebSocket: ride.requested → driver
  │     │     ├─ WebSocket: ride.matched → passenger
  │     │     └─ DEL lock:driver:{driverId}
  │     └─ else: try next candidate
  └─ if no candidates: expand to FALLBACK_RADIUS (5km), repeat
```

---

## 5. Migration Impact

### Backend Files to Create (Phase 1)

```
backend/
├── app/
│   ├── main.py                    NEW — FastAPI app factory
│   ├── config/settings.py         NEW — Pydantic Settings
│   ├── auth/firebase_auth.py      NEW — Firebase Admin SDK + FastAPI deps
│   ├── api/                       NEW — REST endpoints
│   │   ├── health.py
│   │   ├── location.py
│   │   ├── drivers.py
│   │   ├── rides.py
│   │   └── matches.py
│   ├── websocket/                 NEW — WS gateway
│   │   ├── manager.py
│   │   ├── handler.py
│   │   └── events.py
│   ├── schemas/                   NEW — Pydantic request/response
│   │   ├── location.py
│   │   ├── driver.py
│   │   ├── ride.py
│   │   └── event.py
│   ├── models/                    NEW — SQLAlchemy ORM
│   │   ├── user.py
│   │   ├── ride.py
│   │   └── audit.py
│   ├── services/                  NEW — Business logic
│   │   ├── location/
│   │   ├── matching/
│   │   ├── availability/
│   │   ├── rides/
│   │   └── contact/
│   ├── repositories/              NEW — DB access layer
│   ├── redis/                     NEW — Redis layer
│   ├── database/                  NEW — SQLAlchemy setup
│   └── utils/                     NEW — Rate limiting, security
├── tests/                         NEW — pytest suite
├── migrations/                    NEW — Alembic
├── Dockerfile                     NEW
├── docker-compose.yml             NEW
├── .env.example                   NEW
└── requirements.txt               NEW
```

### Flutter Files — Phase 2 Modification Required

| Flutter File | Change Required in Phase 2 | Priority |
|---|---|---|
| `lib/services/driver_location_service.dart` | Add HTTP POST to `/api/location` (parallel with RTDB initially) | HIGH |
| `lib/providers/ride_action_provider.dart` | `bookRide()` → POST `/api/ride-requests` | HIGH |
| `lib/providers/rtdb_provider.dart` | Replace stream providers with WebSocket event providers | HIGH |
| `lib/providers/auth_provider.dart` | Add `getIdToken()` for Authorization header | HIGH |
| `lib/models/driver_location_model.dart` | Remove `phone` from RTDB model | CRITICAL (security) |
| `lib/models/ride_request_model.dart` | Remove `phone` from RTDB model | CRITICAL (security) |
| `lib/models/ride_share_model.dart` | Remove `phone` from RTDB model | CRITICAL (security) |
| `lib/screens/home_screen.dart` | Switch marker data source to WS events | MEDIUM |
| `lib/providers/user_provider.dart` | `sosContactProvider` → backend SOS API | MEDIUM |
| `lib/screens/safety_contacts_screen.dart` | Backend-persisted contacts | LOW |

### RTDB Nodes — Will Become Obsolete in Phase 2

| RTDB Node | Replacement | Notes |
|---|---|---|
| `active_drivers/{uid}` | Redis GEO + WS `driver.presence` events | Phone must be removed before deprecation |
| `ride_requests/{uid}` | Backend `ride_requests` table + WS `ride.requested` events | |
| `ride_shares/{uid}` | Backend ride session service | |

### Riverpod Providers — Will Change in Phase 2

| Provider | Fate |
|---|---|
| `nearbyDriversStreamProvider` | Replaced by WS event stream |
| `nearbyRideRequestsStreamProvider` | Replaced by WS event stream |
| `nearbyRideSharesStreamProvider` | Replaced by WS event stream |
| `rideActionControllerProvider` | bookRide/cancelRide → backend API calls |
| `rtdbServiceProvider` | Deprecated once RTDB is read-only |
| `stableCenterProvider` | Remains (still needed for map center) |
| `currentLocationProvider` | Remains (GPS source) |
| `authStateProvider` | Remains (Firebase Auth stays) |
| `currentUserProvider` | Remains (Firestore profile stays) |

### UI Components — Unchanged in Phase 1 and Phase 2

| Component | Change |
|---|---|
| `lib/screens/home_screen.dart` (FlutterMap, MapOptions, TileLayer) | None |
| `lib/screens/home_screen.dart` (MarkerLayer structure) | None — only data source changes |
| `lib/screens/home_screen.dart` (Bottom nav, FABs) | None |
| `lib/widgets/auto_details_sheet.dart` | None (Phase 2: hide phone, use contact auth) |
| `lib/screens/activity_screen.dart` | None |
| `lib/screens/profile_screen.dart` | None |
| `lib/screens/splash_screen.dart` | None |
| `lib/screens/login_screen.dart` | None |
| `lib/theme/` | None |

---

## 6. Security Improvements in Phase 1

| Problem | Phase 1 Fix | Phase 2 Flutter Integration |
|---|---|---|
| Phone in RTDB | Backend never stores phone in live events | Remove from RTDB models |
| Client-side auth | Firebase Admin SDK token verification | Flutter sends ID token header |
| No driver state machine | Server-authoritative state machine | Flutter observes WS state events |
| No atomic reservation | Redis NX lock + double-check | Booking goes through backend |
| Client-side Haversine | Server-authoritative matching engine | Flutter receives match result |
| No SOS audit | Backend SOS event + audit table | Flutter calls backend SOS API |
| Open RTDB | Unchanged (Phase 2: tighten rules) | RTDB becomes read-mostly, then retired |

---

## 7. Ubuntu Deployment Target

### Development Access

```
Flutter App (Android/iOS)
       │
       │ WiFi / Tailscale
       ▼
Ubuntu Server: 192.168.x.x:8000  (LAN)
       or
Ubuntu Server: 100.x.x.x:8000    (Tailscale)
       │
       ▼
Docker Compose
  ├── FastAPI (0.0.0.0:8000)
  ├── Redis (internal: 6379)
  └── PostgreSQL/PostGIS (internal: 5432)
```

### Future Production

```
Flutter App
       │
       ▼
Domain → Cloudflare / Nginx
       │
       │ HTTPS (443) / WSS (443)
       ▼
Ubuntu Server
       │
       ▼
FastAPI (internal: 8000)
```

### CGNAT / No Public IP Alternative

If the Ubuntu server is behind CGNAT (no public port forwarding):
- **Tailscale** (recommended): Install on server + mobile devices, use Tailscale IP
- **Cloudflare Tunnel**: `cloudflared tunnel` creates a public HTTPS tunnel
- **ngrok**: For development/demo only

---

*End of Phase 1 Architecture Report*
