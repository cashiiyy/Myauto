# MyAuto FastAPI Backend

> **Pure Python FastAPI Backend** — Centralised API, geocoding proxy, routing adapter, and real-time coordination for MyAuto.

---

## 1. Core Architecture Principles

1. **Python FastAPI, NOT Node.js**: The backend is built purely in Python 3.12 with FastAPI, Uvicorn, SQLAlchemy 2.x, Alembic, and GeoAlchemy2.
2. **No `package.json` Required**: No Node.js runtime, npm dependencies, or JavaScript tools are needed for the backend.
3. **Safe Fallback Defaults**: All new database, routing, and verification features default to `false` via feature flags. The application starts cleanly and runs without external service dependencies.
4. **Non-Invasive Preservation**: Firebase Authentication, Realtime Database (`active_drivers`, `ride_shares`), and Firestore paths are 100% preserved.

---

## 2. Default Feature Flags

All new features are guarded by feature flags and **disabled by default**:

| Flag | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_POSTGRES` | `false` | When `false`, the app does not require a PostgreSQL connection. Client uses Firebase / Mock mode. |
| `ENABLE_VALHALLA` | `false` | When `false`, `/api/route` returns `503 Service Unavailable` with a safe notice. |
| `ENABLE_FIREBASE_AUTH` | `false` | When `false`, backend runs without requiring Firebase service account JSON. |

---

## 3. Local Development

### Prerequisites
- Python 3.12+
- Docker & Docker Compose (optional for local full-stack)

### Run with Python Virtualenv
```bash
cd backend
python -m venv venv
# Windows:
.\venv\Scripts\activate
# Linux/macOS:
source venv/bin/activate

pip install -r requirements.txt

# Start local server (defaults to port 8919):
python -m uvicorn app.main:app --host 0.0.0.0 --port 8919 --reload
```

---

## 4. Docker Build & Run

### Build the Production Docker Image
```bash
cd backend
docker build -t myauto-backend:latest .
```

### Run Container Standalone
```bash
docker run -d \
  --name myauto_api \
  -p 8919:8919 \
  -e APP_ENV=production \
  -e APP_PORT=8919 \
  myauto-backend:latest
```

### Test Health Endpoint
```bash
curl -f http://localhost:8919/health
# Response:
# {"status":"ok","service":"myauto-api"}
```

---

## 5. CasaOS / Home Server Deployment

When deploying on CasaOS / Docker UI (e.g., Intel i3, 8GB RAM):

| Parameter | Recommended Value |
| :--- | :--- |
| **Image** | `myauto-backend:latest` |
| **Host Port** | `8919` |
| **Container Port** | `8919` |
| **Network** | `bridge` (or `backend_net` if using Compose) |
| **Restart Policy** | `Unless stopped` |
| **CPU Limit** | `1.0 cores` (Uvicorn single worker) |
| **Memory Limit** | `512 MB` |
| **Volume Mount (Optional)** | `Local /DATA/AppData/myauto/secrets/` ➔ `/app/secrets/` (Read-Only) |

### Environment Variables for CasaOS:
```env
APP_ENV=production
APP_HOST=0.0.0.0
APP_PORT=8919
LOG_LEVEL=info
ENABLE_POSTGRES=false
ENABLE_VALHALLA=false
ENABLE_FIREBASE_AUTH=false
```

---

## 6. Connecting PostgreSQL, Photon, and Valhalla

To enable full self-hosted open-source services via `docker-compose.yml`:

```bash
cd backend
docker compose up -d postgres redis backend valhalla photon
```

To activate them in the FastAPI backend, set in `.env`:
```env
ENABLE_POSTGRES=true
DATABASE_URL=postgresql+asyncpg://myauto:password@postgres:5432/myauto

ENABLE_VALHALLA=true
VALHALLA_URL=http://valhalla:8002

PHOTON_URL=http://photon:2322
```

---

## 7. Running Tests

```bash
cd backend
pytest -v
```
