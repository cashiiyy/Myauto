# MyAuto Centralised Backend (Phase 1)

This repository contains the centralised FastAPI/Redis/PostgreSQL backend for MyAuto.

## Architecture

- **FastAPI**: REST endpoints for location and HTTP actions
- **WebSockets**: Persistent connection for live state updates (presence, ride lifecycle)
- **Redis**: Fast, volatile state (GEO sorted sets, atomic locks, presence TTLs)
- **PostgreSQL / PostGIS**: Durable state and audit logs

## Setup

1. Copy `.env.example` to `.env` and fill in the values.
2. Get the Firebase service account JSON from Firebase Console and place it at `backend/secrets/serviceAccountKey.json`.
3. Run `docker-compose up --build -d`

## Testing

```bash
pytest tests/
```
