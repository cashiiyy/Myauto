# Architecture Overview (Phase 2)

MyAuto uses a centralized, Backend-Primary architecture designed for high throughput, low latency real-time mobility tracking.

## Components

1. **Flutter App (Client)**
   - Firebase Auth for authentication.
   - Riverpod for state management.
   - Dio for REST calls.
   - `web_socket_channel` for WebSocket.
   - Displays real-time nearby drivers on `FlutterMap`.
   - Sends GPS via `DriverLocationService`.

2. **FastAPI Backend (Central Authority)**
   - Python 3.10+ async application.
   - Validates Firebase JWTs.
   - REST API for requests, location updates.
   - WebSocket Manager for real-time dispatching.

3. **Redis (Real-time State & Geospatial)**
   - `GEO` indices (`driver:locations:geo`) for `find_nearest_driver`.
   - Hash maps (`driver:location:{uid}`) for driver state and coordinates.
   - `SET NX` locks for atomic match assignment (prevents double-booking).
   - TTLs on presence keys (auto-expire offline drivers).

4. **PostgreSQL (Persistence)**
   - Stores completed rides, driver profiles, historical data.
   - *(Note: Migrating RTDB profiles to PostgreSQL is planned for Phase 3).*

## Data Flow (Mobility)

1. **Driver GPS:** `Flutter` → `POST /api/location` → `FastAPI` → `Redis GEOADD`
2. **Passenger Search:** `Flutter` → `GET /api/drivers/nearby` → `FastAPI` → `Redis GEOSEARCH`
3. **Ride Request:** 
   - `Flutter` → `POST /api/rides/requests` 
   - `FastAPI` locks driver via `Redis SET NX`
   - `FastAPI` sends `ride.requested` via `WebSocket` to driver
4. **Ride Accept:** 
   - Driver taps "Accept" → `POST /api/matches/{id}/accept`
   - `FastAPI` sends `ride.accepted` via `WebSocket` to passenger.

## Why Backend-Primary?

In Phase 1, the app wrote directly to Firebase RTDB. This caused:
- Race conditions (two passengers booking the same driver).
- Poor battery life (listeners constantly firing).
- Security risks (clients reading other clients' data).

By migrating to FastAPI + Redis:
- We enforce server-side validation.
- We achieve atomic locks on drivers.
- We use WebSockets to push only relevant events (not raw DB streams).
