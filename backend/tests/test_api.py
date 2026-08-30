"""
Backend Integration Tests
=========================

Tests for all API endpoints using httpx.AsyncClient.
Firebase token verification is mocked so tests run without a real Firebase project.
Redis is mocked using fakeredis.

Run:
    cd backend
    pytest tests/ -v --asyncio-mode=auto
"""

from __future__ import annotations

import json
from datetime import datetime, timezone, timedelta
from typing import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock, patch
import time

import pytest
import pytest_asyncio

try:
    import httpx
    from httpx import AsyncClient, ASGITransport
    HAS_HTTPX = True
except ImportError:
    HAS_HTTPX = False

try:
    import fakeredis.aioredis as fake_aioredis
    HAS_FAKEREDIS = True
except ImportError:
    HAS_FAKEREDIS = False

pytestmark = pytest.mark.asyncio


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _make_verified_token(uid: str = "test_driver_uid", email: str = "test@example.com"):
    """Return a mock VerifiedToken."""
    from app.auth.firebase_auth import VerifiedToken
    return VerifiedToken(uid=uid, email=email, email_verified=True, firebase_claims={"uid": uid})


@pytest.fixture
def mock_redis():
    """In-memory Redis for tests."""
    if not HAS_FAKEREDIS:
        pytest.skip("fakeredis not installed — run: pip install fakeredis")
    return fake_aioredis.FakeRedis(decode_responses=True)


@pytest.fixture
def app_with_mocks(mock_redis):
    """Create a FastAPI test app with Firebase auth and Redis mocked."""
    from app.main import create_app
    from app.auth.firebase_auth import get_current_user
    from app.redis.client import get_redis

    app = create_app()

    async def _mock_auth():
        return _make_verified_token()

    async def _mock_redis():
        return mock_redis

    app.dependency_overrides[get_current_user] = _mock_auth
    app.dependency_overrides[get_redis] = _mock_redis
    return app


@pytest_asyncio.fixture
async def client(app_with_mocks) -> AsyncGenerator[AsyncClient, None]:
    """Async HTTP test client."""
    try:
        transport = ASGITransport(app=app_with_mocks)
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            yield c
    except TypeError:
        async with AsyncClient(app=app_with_mocks, base_url="http://test") as c:
            yield c


# ---------------------------------------------------------------------------
# Health endpoint
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_health_returns_200(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body.get("status") == "ok"


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_location_without_auth_returns_401():
    """Calling /api/location without a token must return 401."""
    from app.main import create_app
    app = create_app()

    with patch("app.auth.firebase_auth.init_firebase", return_value=MagicMock()):
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                now_ms = int(time.time() * 1000)
                resp = await client.post(
                    "/api/location",
                    json={
                        "latitude": 8.5241,
                        "longitude": 76.9366,
                        "captured_at": now_ms,
                        "role": "driver",
                    },
                )
        except TypeError:
            async with AsyncClient(app=app, base_url="http://test") as client:
                now_ms = int(time.time() * 1000)
                resp = await client.post(
                    "/api/location",
                    json={
                        "latitude": 8.5241,
                        "longitude": 76.9366,
                        "captured_at": now_ms,
                        "role": "driver",
                    },
                )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Location endpoint
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_driver_location_update_accepted(client):
    now_ms = int(time.time() * 1000)
    resp = await client.post(
        "/api/location",
        json={
            "latitude": 8.5241,
            "longitude": 76.9366,
            "accuracy_meters": 10.0,
            "speed_mps": 5.0,
            "heading_degrees": 90.0,
            "captured_at": now_ms,
            "sequence": 1,
            "role": "driver",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["accepted"] is True
    assert body["freshness"] in ("LIVE", "DELAYED")


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_passenger_location_update_accepted(client):
    now_ms = int(time.time() * 1000)
    resp = await client.post(
        "/api/location",
        json={
            "latitude": 8.5241,
            "longitude": 76.9366,
            "captured_at": now_ms,
            "sequence": 1,
            "role": "passenger",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["accepted"] is True


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_location_invalid_coordinates_returns_422(client):
    now_ms = int(time.time() * 1000)
    resp = await client.post(
        "/api/location",
        json={
            "latitude": 999.0,  # invalid
            "longitude": 76.9366,
            "captured_at": now_ms,
            "role": "driver",
        },
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Nearby drivers endpoint
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_nearby_drivers_returns_list(client):
    """With no drivers registered, should return an empty list."""
    resp = await client.get(
        "/api/drivers/nearby",
        params={"lat": 8.5241, "lng": 76.9366, "radius_km": 2.0},
    )
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_nearby_drivers_returns_registered_driver(client, mock_redis):
    """A driver whose location is registered should appear in the nearby list."""
    from app.redis.geo import geo_add_driver
    from app.redis.keys import RedisKeys

    driver_uid = "test_driver_123"
    driver_lat, driver_lng = 8.5241, 76.9366
    now_ms = int(time.time() * 1000)

    # Manually register a driver in Redis
    await geo_add_driver(mock_redis, driver_uid, driver_lat, driver_lng)
    loc_key = RedisKeys.driver_location(driver_uid)
    await mock_redis.hset(loc_key, mapping={
        "latitude": str(driver_lat),
        "longitude": str(driver_lng),
        "freshness": "LIVE",
        "received_at": str(now_ms),
    })
    avail_key = RedisKeys.driver_availability(driver_uid)
    await mock_redis.set(avail_key, "AVAILABLE", ex=35)

    resp = await client.get(
        "/api/drivers/nearby",
        params={"lat": 8.5241, "lng": 76.9366, "radius_km": 2.0},
    )
    assert resp.status_code == 200
    drivers = resp.json()
    assert any(d["driver_uid"] == driver_uid for d in drivers)
    driver = next(d for d in drivers if d["driver_uid"] == driver_uid)
    assert driver["latitude"] == pytest.approx(driver_lat, abs=0.001)
    assert driver["is_available"] is True


# ---------------------------------------------------------------------------
# Ride requests
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_ride_request_with_no_drivers_returns_expired(client):
    """With no nearby drivers, ride request should return 'expired' status."""
    resp = await client.post(
        "/api/rides/requests",
        json={
            "pickup_lat": 8.5241,
            "pickup_lng": 76.9366,
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "expired"
    assert "request_id" in body


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_ride_request_returns_string_uuid(client):
    """request_id must be a string that looks like a UUID."""
    import re
    UUID_RE = re.compile(
        r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    )
    resp = await client.post(
        "/api/rides/requests",
        json={"pickup_lat": 8.5241, "pickup_lng": 76.9366},
    )
    body = resp.json()
    assert UUID_RE.match(body["request_id"]), (
        f"request_id is not a UUID: {body['request_id']!r}"
    )


# ---------------------------------------------------------------------------
# Destination & Targeted Driver Tests
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_ride_request_with_destination_and_targeted_driver(client, mock_redis):
    """Passenger targets a specific driver with complete destination data."""
    from app.redis.geo import geo_add_driver
    from app.redis.keys import RedisKeys

    driver_uid = "targeted_driver_999"
    driver_lat, driver_lng = 8.5241, 76.9366
    now_ms = int(time.time() * 1000)

    # Register driver in Redis
    await geo_add_driver(mock_redis, driver_uid, driver_lat, driver_lng)
    loc_key = RedisKeys.driver_location(driver_uid)
    await mock_redis.hset(loc_key, mapping={
        "lat": str(driver_lat),
        "lng": str(driver_lng),
        "freshness": "LIVE",
        "received_at": str(now_ms),
    })
    avail_key = RedisKeys.driver_availability(driver_uid)
    await mock_redis.set(avail_key, "AVAILABLE", ex=35)

    resp = await client.post(
        "/api/rides/requests",
        json={
            "pickup_lat": 8.5240,
            "pickup_lng": 76.9365,
            "destination_lat": 8.5300,
            "destination_lng": 76.9400,
            "destination_label": "Central Station",
            "driver_uid": driver_uid,
            "passenger_name": "Test Passenger",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "matching"
    assert body["driver_uid"] == driver_uid


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_ride_request_idempotency(client):
    """Duplicate requests with the same Idempotency-Key should return identical cached response."""
    idempotency_key = "idemp_test_key_12345"

    resp1 = await client.post(
        "/api/rides/requests",
        headers={"Idempotency-Key": idempotency_key},
        json={
            "pickup_lat": 8.5241,
            "pickup_lng": 76.9366,
            "idempotency_key": idempotency_key,
        },
    )
    assert resp1.status_code == 200
    body1 = resp1.json()

    resp2 = await client.post(
        "/api/rides/requests",
        headers={"Idempotency-Key": idempotency_key},
        json={
            "pickup_lat": 8.5241,
            "pickup_lng": 76.9366,
            "idempotency_key": idempotency_key,
        },
    )
    assert resp2.status_code == 200
    body2 = resp2.json()

    assert body1["request_id"] == body2["request_id"]
    assert body1["status"] == body2["status"]


# ---------------------------------------------------------------------------
# Matches — accept / reject
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_accept_match_returns_accepted(client):
    match_id = "some-match-id-123"
    resp = await client.post(f"/api/matches/{match_id}/accept")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "accepted"
    assert body["match_id"] == match_id


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_accept_expired_match_returns_410(client, mock_redis):
    """Attempting to accept an expired ride request should return HTTP 410 Gone."""
    from app.redis.keys import RedisKeys

    match_id = "expired-match-123"
    expired_time = (datetime.now(timezone.utc) - timedelta(seconds=10)).isoformat()

    session_key = RedisKeys.ride_session(match_id)
    await mock_redis.hset(session_key, mapping={
        "passenger_uid": "some_passenger",
        "driver_uid": "test_driver_uid",
        "state": "MATCHED",
        "expires_at": expired_time,
    })

    resp = await client.post(f"/api/matches/{match_id}/accept")
    assert resp.status_code == 410


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_reject_match_returns_rejected(client):
    match_id = "some-match-id-456"
    resp = await client.post(f"/api/matches/{match_id}/reject")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "rejected"


# ---------------------------------------------------------------------------
# Cancel ride
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_cancel_own_ride_succeeds(client, mock_redis):
    """Passenger can cancel their own ride."""
    from app.redis.keys import RedisKeys
    ride_id = "test-ride-to-cancel"
    passenger_uid = "test_driver_uid"

    session_key = RedisKeys.ride_session(ride_id)
    await mock_redis.hset(session_key, mapping={
        "passenger_uid": passenger_uid,
        "state": "SEARCHING",
    })

    resp = await client.post(f"/api/rides/requests/{ride_id}/cancel")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "cancelled"


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_cancel_other_ride_returns_403(client, mock_redis):
    """User cannot cancel someone else's ride."""
    from app.redis.keys import RedisKeys
    ride_id = "other-persons-ride"

    session_key = RedisKeys.ride_session(ride_id)
    await mock_redis.hset(session_key, mapping={
        "passenger_uid": "different_user_uid",
        "state": "SEARCHING",
    })

    resp = await client.post(f"/api/rides/requests/{ride_id}/cancel")
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# SOS
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_sos_returns_acknowledged(client):
    ride_id = "sos-ride-id"
    resp = await client.post(
        f"/api/rides/requests/{ride_id}/sos",
        json={"latitude": 8.5241, "longitude": 76.9366, "message": "Need help!"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["acknowledged"] is True
    assert "sos_event_id" in body


# ---------------------------------------------------------------------------
# Driver Pending Ride Recovery
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_driver_pending_ride_returns_none_when_empty(client):
    """Driver checking for pending rides when none exist returns has_pending=False."""
    resp = await client.get("/api/rides/driver/pending")
    assert resp.status_code == 200
    body = resp.json()
    assert body["has_pending"] is False
    assert body["ride"] is None

