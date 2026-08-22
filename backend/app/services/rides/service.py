"""
Rides Service
=============

Coordinates the full ride lifecycle.
Integrates matching, locking, DB writes, and WebSocket events.
"""

from __future__ import annotations

import logging
from uuid import UUID

import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.ride import CreateRideRequest
from app.services.matching.engine import find_nearest_driver
from app.services.availability.service import update_driver_state
from app.redis.keys import RedisKeys
# TODO: DB insertions for RideRequest, RideMatch, RideEvent

logger = logging.getLogger(__name__)


async def create_ride_request(
    db: AsyncSession,
    redis: aioredis.Redis,
    request: CreateRideRequest,
    passenger_uid: str,
) -> dict:
    """
    1. Create RideRequest in DB
    2. Call matching engine to find best driver
    3. If found, create RideMatch in DB
    4. Transition driver to CONTACTED
    5. Return result
    """
    # For Phase 1, we will simulate the DB writes until the repositories are fully wired.
    # In a real flow:
    # req = await ride_repo.create_request(db, passenger_uid, request)
    # ride_id = str(req.id)
    ride_id = "temp-uuid-for-now"
    
    logger.info("Passenger %s requested ride from %s, %s", passenger_uid, request.pickup_lat, request.pickup_lng)
    
    driver_uid = await find_nearest_driver(redis, db, request, passenger_uid, ride_id)
    
    if not driver_uid:
        return {
            "status": "expired",
            "message": "No eligible drivers found nearby.",
            "request_id": ride_id
        }

    # Match found! Transition driver
    # The matching engine holds the lock. We transition, then release.
    try:
        await update_driver_state(redis, driver_uid, "CONTACTED")
        # await ride_repo.create_match(db, req.id, driver_uid)
        logger.info("Ride %s matched to driver %s", ride_id, driver_uid)
    finally:
        # Release the lock that was acquired by find_nearest_driver
        from app.redis.locks import release_driver_lock
        await release_driver_lock(redis, driver_uid, passenger_uid)

    # Note: WebSocket events (ride.requested, ride.matched) would be dispatched here
    return {
        "status": "matching",
        "message": "Match found, waiting for driver response.",
        "request_id": ride_id,
        "driver_uid": driver_uid
    }
