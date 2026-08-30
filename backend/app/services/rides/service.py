"""
Rides Service
=============

Coordinates the full ride lifecycle.
Integrates matching, locking, DB writes, idempotency, and WebSocket events.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone, timedelta
from uuid import UUID, uuid4
from typing import Optional

import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.redis.keys import RedisKeys
from app.repositories.ride_repository import RideRepository
from app.schemas.ride import CreateRideRequest
from app.services.matching.engine import find_nearest_driver
from app.services.matching.haversine import haversine_distance_km
from app.services.availability.service import update_driver_state
from app.services.firebase_adapter import FirebaseAuthAdapter
from app.websocket.manager import manager
from app.schemas.event import WebSocketEvent, EventType

logger = logging.getLogger(__name__)


async def create_ride_request(
    db: AsyncSession,
    redis: aioredis.Redis,
    request: CreateRideRequest,
    passenger_uid: str,
    correlation_id: Optional[str] = None,
) -> dict:
    """
    Creates a ride request with full idempotency, destination support, atomic driver reservation,
    PostgreSQL persistence, and multi-worker WebSocket dispatch.
    """
    # ── 1. Idempotency Check ───────────────────────────────────────────────────
    if request.idempotency_key:
        idemp_redis_key = RedisKeys.idempotency_ride(request.idempotency_key)
        try:
            cached_raw = await redis.get(idemp_redis_key)
            if cached_raw:
                logger.info("Idempotency hit for key %s", request.idempotency_key)
                return json.loads(cached_raw)
        except Exception as e:
            logger.debug("Redis idempotency read failed: %s", e)

        # Check DB repository for existing ride with this idempotency key
        try:
            ride_repo = RideRepository(db)
            existing_ride = await ride_repo.get_by_idempotency_key(request.idempotency_key)
            if existing_ride:
                logger.info("Database idempotency hit for key %s", request.idempotency_key)
                return {
                    "status": existing_ride.status,
                    "message": "Ride request already received.",
                    "request_id": str(existing_ride.id),
                    "driver_uid": existing_ride.driver_uid or existing_ride.selected_driver_uid,
                }
        except Exception as e:
            logger.debug("DB idempotency check failed: %s", e)

    ride_id = str(uuid4())
    now_utc = datetime.now(timezone.utc)
    expires_at = now_utc + timedelta(seconds=30)
    expires_at_iso = expires_at.isoformat()

    logger.info(
        "[DIAG][RideService] Passenger %s requested ride from (%.6f, %.6f) to (%s, %s) — ride_id=%s, target_driver=%s, correlation_id=%s",
        passenger_uid,
        request.pickup_lat,
        request.pickup_lng,
        request.destination_lat,
        request.destination_lng,
        ride_id,
        request.driver_uid,
        correlation_id,
    )

    # ── 2. Passenger Name Resolution ───────────────────────────────────────────
    passenger_name = request.passenger_name
    if not passenger_name:
        try:
            auth_adapter = FirebaseAuthAdapter()
            passenger_name = await auth_adapter.get_user_display_name(passenger_uid)
        except Exception:
            pass
    passenger_name = passenger_name or "Passenger"

    # ── 3. Distance & Duration Estimation ──────────────────────────────────────
    approx_distance_km: Optional[float] = None
    estimated_duration_min: Optional[int] = None
    if request.destination_lat is not None and request.destination_lng is not None:
        approx_distance_km = round(
            haversine_distance_km(
                request.pickup_lat,
                request.pickup_lng,
                request.destination_lat,
                request.destination_lng,
            ),
            2,
        )
        # Assuming average auto-rickshaw speed of 25 km/h in city conditions
        estimated_duration_min = max(1, int((approx_distance_km / 25.0) * 60))

    # ── 4. Initialize Redis Session ───────────────────────────────────────────
    session_key = RedisKeys.ride_session(ride_id)
    session_mapping = {
        "ride_id": ride_id,
        "passenger_uid": passenger_uid,
        "passenger_name": passenger_name,
        "state": "SEARCHING",
        "pickup_lat": str(request.pickup_lat),
        "pickup_lng": str(request.pickup_lng),
        "expires_at": expires_at_iso,
    }
    if request.destination_lat is not None:
        session_mapping["destination_lat"] = str(request.destination_lat)
        session_mapping["destination_lng"] = str(request.destination_lng)
    if request.destination_label:
        session_mapping["destination_label"] = request.destination_label
    if request.notes:
        session_mapping["notes"] = request.notes
    if request.idempotency_key:
        session_mapping["idempotency_key"] = request.idempotency_key

    await redis.hset(session_key, mapping=session_mapping)
    await redis.expire(session_key, 120)

    # ── 5. Run Matching Engine (Atomic lock acquired if found) ─────────────────
    driver_uid = await find_nearest_driver(
        redis, db, request, passenger_uid, ride_id
    )

    if not driver_uid:
        await redis.delete(session_key)
        logger.info(
            "No eligible drivers found for passenger %s (ride %s)",
            passenger_uid,
            ride_id,
        )
        response_data = {
            "status": "expired",
            "message": "Selected driver or nearby drivers are currently unavailable.",
            "request_id": ride_id,
            "driver_uid": None,
        }
        if request.idempotency_key:
            try:
                idemp_redis_key = RedisKeys.idempotency_ride(request.idempotency_key)
                await redis.set(idemp_redis_key, json.dumps(response_data), ex=120)
            except Exception as e:
                logger.debug("Redis idempotency write failed: %s", e)
        return response_data

    # ── 6. Driver Matched: Update state & DB ────────────────────────────────────
    try:
        await update_driver_state(redis, driver_uid, "CONTACTED")
        await redis.hset(session_key, mapping={
            "driver_uid": driver_uid,
            "state": "MATCHED",
        })
        await redis.expire(session_key, 3600)
        logger.info("Ride %s matched: driver=%s passenger=%s", ride_id, driver_uid, passenger_uid)

        # Persist to PostgreSQL
        try:
            ride_repo = RideRepository(db)
            await ride_repo.create_ride_request(
                passenger_uid=passenger_uid,
                pickup_lat=request.pickup_lat,
                pickup_lon=request.pickup_lng,
                dropoff_lat=request.destination_lat,
                dropoff_lon=request.destination_lng,
                destination_label=request.destination_label,
                selected_driver_uid=request.driver_uid,
                passenger_name=passenger_name,
                idempotency_key=request.idempotency_key,
                notes=request.notes,
                ride_id=UUID(ride_id),
                request_expires_at=expires_at,
            )
            await db.commit()
        except Exception as db_err:
            logger.warning("PostgreSQL ride persistence failed (proceeding with Redis session): %s", db_err)
            await db.rollback()

    except Exception as match_err:
        from app.redis.locks import release_driver_lock
        await release_driver_lock(redis, driver_uid, passenger_uid)
        logger.error("Ride matching state/persistence failed for driver %s: %s", driver_uid, match_err)
        raise

    # ── 7. Dispatch WebSocket Events ──────────────────────────────────────────

    # Notify DRIVER with complete trip payload
    driver_payload = {
        "passenger_uid": passenger_uid,
        "passenger_name": passenger_name,
        "pickup_lat": request.pickup_lat,
        "pickup_lng": request.pickup_lng,
        "accuracy_meters": request.pickup_accuracy_meters,
        "destination_lat": request.destination_lat,
        "destination_lng": request.destination_lng,
        "destination_label": request.destination_label or "Selected Destination",
        "approx_distance_km": approx_distance_km,
        "estimated_duration_min": estimated_duration_min,
        "notes": request.notes,
        "match_id": ride_id,
        "expires_at": expires_at_iso,
    }
    driver_event = WebSocketEvent(
        type=EventType.RIDE_REQUESTED,
        ride_id=ride_id,
        payload=driver_payload,
    )
    logger.info(
        "[DIAG][RideService] Dispatching ride.requested to driver=%s (ride_id=%s, expires_at=%s)",
        driver_uid,
        ride_id,
        expires_at_iso,
    )
    await manager.send_personal_message(driver_event, driver_uid)

    # Notify PASSENGER
    passenger_event = WebSocketEvent(
        type=EventType.RIDE_MATCHED,
        ride_id=ride_id,
        payload={
            "driver_uid": driver_uid,
            "match_id": ride_id,
            "message": "Driver found. Waiting for driver confirmation.",
        },
    )
    logger.info(
        "[DIAG][RideService] Dispatching ride.matched to passenger=%s (driver=%s, ride_id=%s)",
        passenger_uid,
        driver_uid,
        ride_id,
    )
    await manager.send_personal_message(passenger_event, passenger_uid)

    response_data = {
        "status": "matching",
        "message": "Match found, waiting for driver response.",
        "request_id": ride_id,
        "driver_uid": driver_uid,
    }

    # ── 8. Cache Idempotency Response ──────────────────────────────────────────
    if request.idempotency_key:
        try:
            idemp_redis_key = RedisKeys.idempotency_ride(request.idempotency_key)
            await redis.set(idemp_redis_key, json.dumps(response_data), ex=120)
        except Exception as e:
            logger.debug("Redis idempotency write failed: %s", e)

    return response_data
