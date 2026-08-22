"""
Location Service
================

Processes incoming location updates and persists them to Redis.
"""

from __future__ import annotations

import logging
import time

import redis.asyncio as aioredis

from app.redis.geo import geo_add_driver
from app.redis.keys import RedisKeys
from app.redis.presence import refresh_driver_ttl
from app.schemas.location import LocationUpdate, StoredLocation
from app.services.location.freshness import determine_freshness
from app.services.location.validator import validate_location_update

logger = logging.getLogger(__name__)


async def process_driver_location(
    update: LocationUpdate,
    driver_uid: str,
    redis: aioredis.Redis,
) -> StoredLocation:
    """
    Process a driver's location update and store it in Redis.
    """
    server_time_ms = int(time.time() * 1000)

    # Validation
    is_valid, err_msg = await validate_location_update(update, driver_uid, redis)
    if not is_valid:
        raise ValueError(err_msg)

    # Freshness
    freshness = determine_freshness(update, server_time_ms)
    if freshness == "OFFLINE":
        raise ValueError("Location update is too old (OFFLINE state)")

    # Build stored object
    stored = StoredLocation(
        uid=driver_uid,
        latitude=update.latitude,
        longitude=update.longitude,
        accuracy_meters=update.accuracy_meters,
        speed_mps=update.speed_mps,
        heading_degrees=update.heading_degrees,
        altitude=update.altitude,
        captured_at=update.captured_at,
        received_at=server_time_ms,
        sequence=update.sequence,
        freshness=freshness,
    )

    # Save to Redis
    # 1. GEO sorted set
    await geo_add_driver(redis, driver_uid, update.latitude, update.longitude)

    # 2. Location hash
    key = RedisKeys.driver_location(driver_uid)
    
    # Store everything as strings in the hash
    mapping = {
        k: str(v) for k, v in stored.model_dump().items() if v is not None
    }
    
    await redis.hset(key, mapping=mapping)
    
    # 3. Refresh TTLs on presence, availability, and location keys
    await refresh_driver_ttl(redis, driver_uid)

    return stored


async def process_passenger_location(
    update: LocationUpdate,
    passenger_uid: str,
    redis: aioredis.Redis,
) -> StoredLocation:
    """
    Process a passenger's location update and store it in Redis.
    """
    server_time_ms = int(time.time() * 1000)

    is_valid, err_msg = await validate_location_update(update, passenger_uid, redis)
    if not is_valid:
        raise ValueError(err_msg)

    freshness = determine_freshness(update, server_time_ms)
    
    stored = StoredLocation(
        uid=passenger_uid,
        latitude=update.latitude,
        longitude=update.longitude,
        accuracy_meters=update.accuracy_meters,
        speed_mps=update.speed_mps,
        heading_degrees=update.heading_degrees,
        altitude=update.altitude,
        captured_at=update.captured_at,
        received_at=server_time_ms,
        sequence=update.sequence,
        freshness=freshness,
    )

    key = RedisKeys.passenger_location(passenger_uid)
    mapping = {k: str(v) for k, v in stored.model_dump().items() if v is not None}
    await redis.hset(key, mapping=mapping)
    await redis.expire(key, 60)  # Passenger TTL

    return stored
