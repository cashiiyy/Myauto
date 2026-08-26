# Backend Setup Guide

This guide walks through setting up, deploying, and operating the MyAuto Python FastAPI backend.

---

## 1. Directory Structure

```
backend/
├── Dockerfile                  # Multi-stage Python 3.12 slim Dockerfile
├── requirements.txt            # Pinned dependencies
├── alembic.ini                 # Database migration config
├── .env.example                # Safe environment variable template
├── .dockerignore               # Build context exclusions
├── migrations/                 # Alembic migrations directory
│   ├── env.py                  # Migration runner registering models
│   ├── script.py.mako          # Migration template
│   └── versions/               # Versioned migration scripts
└── app/
    ├── __init__.py
    ├── main.py                 # FastAPI app entry point & lifespan manager
    ├── core/
    │   ├── __init__.py
    │   └── config.py           # Pydantic Settings & feature flags
    ├── db/
    │   ├── __init__.py
    │   ├── session.py          # Async SQLAlchemy engine & session factory
    │   └── models.py           # PostGIS-enabled ORM models
    ├── api/
    │   ├── __init__.py         # Aggregated router
    │   ├── health.py           # GET /health & GET /ready
    │   ├── geocoding.py        # GET /api/geocode/search (Photon client)
    │   └── routing.py          # GET/POST /api/route (Valhalla client)
    ├── repositories/
    │   ├── __init__.py
    │   ├── user_repository.py  # User persistence
    │   ├── driver_repository.py# Driver & DriverLocation PostGIS queries
    │   └── ride_repository.py  # Ride persistence
    └── services/
        ├── __init__.py
        ├── photon_service.py   # Photon HTTPX client
        ├── valhalla_service.py # Valhalla HTTPX client
        └── firebase_adapter.py # Firebase Auth/RTDB/Firestore adapters
```

---

## 2. Environment Variables Configuration

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Key environment settings:
- `APP_PORT=8919`: Default HTTP port.
- `ENABLE_POSTGRES=false`: Set to `true` once PostgreSQL + PostGIS container is running.
- `ENABLE_VALHALLA=false`: Set to `true` when routing engine is enabled.
- `ENABLE_FIREBASE_AUTH=false`: Set to `true` when validating Firebase ID tokens on backend.

---

## 3. Database Migrations

When `ENABLE_POSTGRES=true`:

```bash
# Run migrations up to latest version
alembic upgrade head

# Rollback one migration if needed
alembic downgrade -1
```

---

## 4. Health & Verification

Once running, verify:
- **Liveness probe:** `curl http://localhost:8919/health` ➔ `{"status": "ok", "service": "myauto-api"}`
- **Readiness probe:** `curl http://localhost:8919/ready` ➔ `{"status": "ready", "database": "disabled"}`
- **Geocoding search:** `curl "http://localhost:8919/api/geocode/search?q=Kollam"`
