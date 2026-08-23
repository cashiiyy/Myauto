"""
Rides Service
=============

Coordinates the full ride lifecycle.
Integrates matching, locking, DB writes, and WebSocket events.
"""

from __future__ import annotations

import logging
from uuid import uuid4

import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.redis.keys import RedisKeys
from app.schemas.ride import CreateRideRequest
from app.services.matching.engine import find_nearest_driver
from app.services.availability.service import update_driver_state
from app.websocket.manager import manager
from app.schemas.event import WebSocketEvent, EventType

logger = logging.getLogger(__name__)


async def create_ride_request(
    db: AsyncSession,
    redis: aioredis.Redis,
    request: CreateRideRequest,
    passenger_uid: str,
) -> dict:
    """
    1. Generate a real ride request UUID
    2. Store ride session in Redis
    3. Call matching engine to find best driver
    4. If found, create RideMatch in Redis, transition driver to CONTACTED
    5. Dispatch WebSocket events to both parties
    6. Return result
    """
    ride_id = str(uuid4())

    logger.info(
        "Passenger %s requested ride from (%.6f, %.6f) — ride_id=%s",
        passenger_uid,
        request.pickup_lat,
        request.pickup_lng,
        ride_id,
    )

    # Store minimal session so cancel can find it
    session_key = RedisKeys.ride_session(ride_id)
    await redis.hset(session_key, mapping={
        "passenger_uid": passenger_uid,
        "state": "SEARCHING",
        "pickup_lat": str(request.pickup_lat),
        "pickup_lng": str(request.pickup_lng),
    })
    await redis.expire(session_key, 120)  # expires if no match found

    # Find nearest eligible driver
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
        return {
            "status": "expired",
            "message": "No eligible drivers found nearby.",
            "request_id": ride_id,
        }

    # Match found — transition driver to CONTACTED and update session
    try:
        await update_driver_state(redis, driver_uid, "CONTACTED")
        await redis.hset(session_key, mapping={
            "driver_uid": driver_uid,
            "state": "MATCHED",
        })
        await redis.expire(session_key, 3600)
        logger.info("Ride %s matched: driver=%s passenger=%s", ride_id, driver_uid, passenger_uid)
    except Exception:
        from app.redis.locks import release_driver_lock
        await release_driver_lock(redis, driver_uid, passenger_uid)
        raise
    finally:
        # Release the atomic lock acquired by find_nearest_driver
        from app.redis.locks import release_driver_lock
        await release_driver_lock(redis, driver_uid, passenger_uid)

    # ── WebSocket events ──────────────────────────────────────────────────────

    # Notify DRIVER: a passenger is requesting a ride
    driver_event = WebSocketEvent(
        type=EventType.RIDE_REQUESTED,
        ride_id=ride_id,
        payload={
            "passenger_uid": passenger_uid,
            "pickup_lat": request.pickup_lat,
            "pickup_lng": request.pickup_lng,
            "accuracy_meters": request.pickup_accuracy_meters,
            "notes": request.notes,
            "match_id": ride_id,
        },
    )
    await manager.send_personal_message(driver_event, driver_uid)

    # Notify PASSENGER: a driver has been matched
    passenger_event = WebSocketEvent(
        type=EventType.RIDE_MATCHED,
        ride_id=ride_id,
        payload={
            "driver_uid": driver_uid,
            "match_id": ride_id,
            "message": "Driver found. Waiting for driver confirmation.",
        },
    )
    await manager.send_personal_message(passenger_event, passenger_uid)

    return {
        "status": "matching",
        "message": "Match found, waiting for driver response.",
        "request_id": ride_id,
        "driver_uid": driver_uid,
    }
