# MyAuto Backend API Specification

Base URL: `http://<host>:8919`

---

## 1. System & Health Endpoints

### GET `/health`
- **Description:** Basic liveness probe.
- **Response:**
  ```json
  {
    "status": "ok",
    "service": "myauto-api"
  }
  ```

### GET `/ready`
- **Description:** Readiness probe that verifies internal subsystems (PostgreSQL connectivity when `ENABLE_POSTGRES=true`).
- **Response (200 OK):**
  ```json
  {
    "status": "ready",
    "service": "myauto-api",
    "database": "connected",
    "environment": "production"
  }
  ```

---

## 2. Geocoding Endpoints (Photon)

### GET `/api/geocode/search`
- **Description:** Queries the Photon search engine for destination autocomplete.
- **Parameters:**
  - `q` (string, required): Search query (e.g. `Kollam Railway Station`). Minimum length 1.
  - `limit` (integer, optional, default: `5`): Maximum results to return (1–15).
  - `lat` (float, optional): Latitude for location proximity bias.
  - `lon` (float, optional): Longitude for location proximity bias.
  - `bbox` (string, optional): Bounding box `minLon,minLat,maxLon,maxLat`.
- **Response (200 OK):**
  ```json
  [
    {
      "name": "Kollam Junction",
      "display_name": "Kollam Junction, Chamakkada, Kollam, Kerala, India",
      "latitude": 8.8872,
      "longitude": 76.5954,
      "city": "Kollam",
      "state": "Kerala",
      "country": "India",
      "osm_type": "N"
    }
  ]
  ```
- **Errors:**
  - `400 Bad Request`: Empty query string.
  - Returns `[]` on backend timeout or Photon downtime without leaking errors.

---

## 3. Routing Endpoints (Valhalla)

*Guarded by `ENABLE_VALHALLA` flag. Returns `503 Service Unavailable` when disabled.*

### GET `/api/route`
- **Parameters:** `from_lat`, `from_lon`, `to_lat`, `to_lon`, `costing` (default: `auto`).

### POST `/api/route`
- **Request Body:**
  ```json
  {
    "from_lat": 8.8932,
    "from_lon": 76.6141,
    "to_lat": 8.9100,
    "to_lon": 76.6300,
    "costing": "auto"
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "distance_km": 4.52,
    "duration_seconds": 540,
    "shape": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
    "units": "kilometres"
  }
  ```
