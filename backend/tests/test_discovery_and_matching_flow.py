"""
Test Driver Discovery and Matching Engine Flow
==============================================
Validates the full pipeline:
- GPS Location Ingestion & Freshness
- Sequence reset acceptance on driver app restart
- Redis GEO Indexing and Location Hash
- Targeted driver selection & proximity matching
"""

import time
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
import fakeredis.aioredis as fakeredis

from app.main import create_app
from app.redis.client import get_redis
from app.redis.keys import RedisKeys
from app.auth.firebase_auth import get_current_user, VerifiedToken


@pytest.fixture
def fake_driver_token():
    return VerifiedToken(uid="driver_auto_42", email="driver42@myauto.test")


@pytest.fixture
def fake_passenger_token():
    return VerifiedToken(uid="passenger_77", email="passenger77@myauto.test")


@pytest_asyncio.fixture
async def app_with_fakeredis():
    redis = await fakeredis.FakeRedis(decode_responses=True)
    app = create_app()
    app.dependency_overrides[get_redis] = lambda: redis

    yield app, redis

    await redis.aclose()


@pytest.mark.asyncio
async def test_driver_sequence_reset_on_app_restart(app_with_fakeredis, fake_driver_token):
    app, redis = app_with_fakeredis
    app.dependency_overrides[get_current_user] = lambda: fake_driver_token

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        now_ms = int(time.time() * 1000)
        # 1. First session: driver sends seq 1, 2, 3
        for seq in [1, 2, 3]:
            resp = await client.post("/api/location", json={
                "latitude": 8.5241,
                "longitude": 76.9366,
                "captured_at": now_ms + (seq * 1000),
                "sequence": seq,
                "role": "driver",
            })
            assert resp.status_code == 200
            assert resp.json()["accepted"] is True

        # 2. Driver app restarts: sequence resets to 1 (new session)
        resp = await client.post("/api/location", json={
            "latitude": 8.5245,
            "longitude": 76.9370,
            "captured_at": now_ms + 5000,
            "sequence": 1,
            "role": "driver",
        })
        assert resp.status_code == 200
        assert resp.json()["accepted"] is True, "Sequence reset to 1 on restart must be accepted"


@pytest.mark.asyncio
async def test_targeted_driver_matching_with_hash_coordinates(app_with_fakeredis, fake_driver_token, fake_passenger_token):
    app, redis = app_with_fakeredis

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        now_ms = int(time.time() * 1000)
        # 1. Driver posts location
        app.dependency_overrides[get_current_user] = lambda: fake_driver_token
        driver_loc_resp = await client.post("/api/location", json={
            "latitude": 8.524133,
            "longitude": 76.936612,
            "accuracy_meters": 4.5,
            "captured_at": now_ms,
            "sequence": 1,
            "role": "driver",
        })
        assert driver_loc_resp.status_code == 200
        assert driver_loc_resp.json()["freshness"] == "LIVE"

        # 2. Passenger queries nearby drivers
        app.dependency_overrides[get_current_user] = lambda: fake_passenger_token
        nearby_resp = await client.get("/api/drivers/nearby", params={
            "lat": 8.5240,
            "lng": 76.9365,
            "radius_km": 2.0,
        })
        assert nearby_resp.status_code == 200
        drivers = nearby_resp.json()
        assert len(drivers) == 1
        assert drivers[0]["driver_uid"] == "driver_auto_42"
        assert drivers[0]["is_available"] is True
        assert abs(drivers[0]["latitude"] - 8.524133) < 0.0001
        assert abs(drivers[0]["longitude"] - 76.936612) < 0.0001

        # 3. Passenger targets specific driver for booking
        ride_resp = await client.post("/api/rides/requests", json={
            "pickup_lat": 8.5240,
            "pickup_lng": 76.9365,
            "destination_lat": 8.5300,
            "destination_lng": 76.9450,
            "destination_label": "Central Station",
            "driver_uid": "driver_auto_42",
            "passenger_name": "Test Passenger",
            "idempotency_key": f"idemp_test_{now_ms}",
        })
        assert ride_resp.status_code == 200
        ride_data = ride_resp.json()
        assert ride_data["status"] == "matching"
        assert ride_data["driver_uid"] == "driver_auto_42"
        assert "request_id" in ride_data
