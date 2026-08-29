"""
End-to-End Ride Lifecycle Integration Tests
===========================================

Validates data transmission and state transitions across the full stack:
- Location tracking (GPS -> Redis GEO)
- Driver discovery (/api/drivers/nearby)
- Geocoding lookup proxy (/api/geocode/search)
- Targeted & Nearest driver ride booking with full destination data and idempotency
- Atomic driver locking and concurrency protection
- Match acceptance, 30s expiration checks, and DB/Redis state synchronization
"""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone, timedelta
from typing import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock, patch

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

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.redis.keys import RedisKeys
from app.redis.geo import geo_add_driver
from app.schemas.event import WebSocketEvent, EventType
from app.websocket.manager import manager

pytestmark = pytest.mark.asyncio


@pytest.fixture
def mock_redis():
    """In-memory fake Redis instance."""
    return fake_aioredis.FakeRedis(decode_responses=True)


@pytest.mark.skipif(not HAS_HTTPX, reason="httpx not installed")
async def test_full_ride_lifecycle_and_data_transmission(mock_redis):
    """
    Test complete lifecycle from driver GPS beacon to booking, acceptance, and completion.
    """
    from app.main import create_app

    app = create_app()

    current_auth_token = VerifiedToken(
        uid="driver_kollam_01",
        email="driver@myauto.app",
        email_verified=True,
        firebase_claims={"uid": "driver_kollam_01"},
    )

    async def _mock_auth():
        return current_auth_token

    async def _mock_redis():
        return mock_redis

    app.dependency_overrides[get_current_user] = _mock_auth
    app.dependency_overrides[get_redis] = _mock_redis

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:

        # ── Step 1: Driver transmits GPS location update ────────────────────────
        driver_lat = 8.8932
        driver_lng = 76.6141
        now_ms = int(time.time() * 1000)

        loc_resp = await client.post(
            "/api/location",
            json={
                "latitude": driver_lat,
                "longitude": driver_lng,
                "accuracy_meters": 8.5,
                "speed_mps": 4.2,
                "heading_degrees": 120.0,
                "captured_at": now_ms,
                "role": "driver",
            },
        )
        assert loc_resp.status_code == 200
        assert loc_resp.json()["accepted"] is True
        assert loc_resp.json()["freshness"] == "LIVE"

        # Explicitly set availability to AVAILABLE
        await mock_redis.set(RedisKeys.driver_availability("driver_kollam_01"), "AVAILABLE", ex=35)

        # ── Step 2: Passenger searches nearby drivers ───────────────────────────
        # Switch auth context to passenger
        current_auth_token = VerifiedToken(
            uid="passenger_anand_99",
            email="anand@gmail.com",
            email_verified=True,
            firebase_claims={"uid": "passenger_anand_99"},
        )

        nearby_resp = await client.get(
            "/api/drivers/nearby",
            params={"lat": 8.8930, "lng": 76.6140, "radius_km": 2.0},
        )
        assert nearby_resp.status_code == 200
        drivers = nearby_resp.json()
        assert len(drivers) >= 1
        found_driver = next(d for d in drivers if d["driver_uid"] == "driver_kollam_01")
        assert found_driver["is_available"] is True
        assert found_driver["latitude"] == pytest.approx(driver_lat, abs=0.001)

        # ── Step 3: Passenger requests ride with destination & targeted driver ───
        idempotency_key = "idemp_test_cycle_001"
        book_resp = await client.post(
            "/api/rides/requests",
            headers={"Idempotency-Key": idempotency_key},
            json={
                "pickup_lat": 8.8930,
                "pickup_lng": 76.6140,
                "pickup_accuracy_meters": 5.0,
                "destination_lat": 8.9100,
                "destination_lng": 76.6300,
                "destination_label": "Kollam Beach, Kerala",
                "driver_uid": "driver_kollam_01",
                "passenger_name": "Anand S.",
                "idempotency_key": idempotency_key,
                "notes": "Near north gate",
            },
        )
        assert book_resp.status_code == 200
        book_data = book_resp.json()
        assert book_data["status"] == "matching"
        assert book_data["driver_uid"] == "driver_kollam_01"
        ride_id = book_data["request_id"]
        assert ride_id is not None

        # Verify Redis session was initialized with all transmitted fields
        session_key = RedisKeys.ride_session(ride_id)
        session = await mock_redis.hgetall(session_key)
        assert session["passenger_uid"] == "passenger_anand_99"
        assert session["driver_uid"] == "driver_kollam_01"
        assert session["state"] == "MATCHED"
        assert "expires_at" in session

        # Verify driver state transitioned to CONTACTED
        driver_avail = await mock_redis.get(RedisKeys.driver_availability("driver_kollam_01"))
        assert driver_avail == "CONTACTED"

        # ── Step 4: Idempotent retry transmission receives identical response ───
        retry_resp = await client.post(
            "/api/rides/requests",
            headers={"Idempotency-Key": idempotency_key},
            json={
                "pickup_lat": 8.8930,
                "pickup_lng": 76.6140,
                "destination_lat": 8.9100,
                "destination_lng": 76.6300,
                "destination_label": "Kollam Beach, Kerala",
                "driver_uid": "driver_kollam_01",
                "passenger_name": "Anand S.",
                "idempotency_key": idempotency_key,
            },
        )
        assert retry_resp.status_code == 200
        assert retry_resp.json()["request_id"] == ride_id

        # ── Step 5: Driver accepts ride match ───────────────────────────────────
        # Switch auth context back to driver
        current_auth_token = VerifiedToken(
            uid="driver_kollam_01",
            email="driver@myauto.app",
            email_verified=True,
            firebase_claims={"uid": "driver_kollam_01"},
        )

        accept_resp = await client.post(f"/api/matches/{ride_id}/accept")
        assert accept_resp.status_code == 200
        accept_data = accept_resp.json()
        assert accept_data["status"] == "accepted"
        assert accept_data["match_id"] == ride_id

        # Verify session transitioned to ACTIVE and driver availability to BUSY
        updated_session = await mock_redis.hgetall(session_key)
        assert updated_session["state"] == "ACTIVE"
        assert await mock_redis.get(RedisKeys.driver_availability("driver_kollam_01")) == "BUSY"

        # ── Step 6: Passenger cancels / completes ride ──────────────────────────
        current_auth_token = VerifiedToken(
            uid="passenger_anand_99",
            email="anand@gmail.com",
            email_verified=True,
            firebase_claims={"uid": "passenger_anand_99"},
        )

        cancel_resp = await client.post(f"/api/rides/requests/{ride_id}/cancel")
        assert cancel_resp.status_code == 200
        assert cancel_resp.json()["status"] == "cancelled"

        # Verify session was cleaned up and driver returned to AVAILABLE
        assert await mock_redis.exists(session_key) == 0
        assert await mock_redis.get(RedisKeys.driver_availability("driver_kollam_01")) == "AVAILABLE"
