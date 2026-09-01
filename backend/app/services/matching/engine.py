"""
Nearest Driver Engine
======================

The core algorithm for selecting the best driver for a passenger request.
Enforces atomicity and eligibility for both auto-matching and passenger-targeted driver requests.
"""

from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.config.settings import get_settings
from app.redis.geo import geo_search_drivers, geo_get_position
from app.redis.locks import acquire_driver_lock, release_driver_lock
from app.schemas.ride import CreateRideRequest
from app.services.matching.eligibility import is_driver_eligible
from app.services.matching.haversine import haversine_distance_km

logger = logging.getLogger(__name__)


async def find_nearest_driver(
    redis: aioredis.Redis,
    db: AsyncSession,
    request: CreateRideRequest,
    passenger_uid: str,
    ride_id: str,
) -> Optional[str]:
    """
    Find and atomically reserve an eligible driver.
    If request.driver_uid is specified, validates and locks that specific driver.
    Otherwise, performs a multi-ring proximity search.
    """
    settings = get_settings()

    # ── Path A: Passenger selected a specific driver UID ───────────────────────
    if request.driver_uid:
        driver_uid = request.driver_uid.strip()
        logger.info(
            "Passenger %s targeted specific driver %s for ride %s",
            passenger_uid,
            driver_uid,
            ride_id,
        )

        # 1. Eligibility pre-check (must be AVAILABLE, LIVE/DELAYED, not rejected)
        if not await is_driver_eligible(redis, driver_uid, ride_id):
            logger.warning("Targeted driver %s is currently ineligible", driver_uid)
            return None

        # 2. Radius and distance check
        pos = await geo_get_position(redis, driver_uid)
        if not pos:
            # Check location hash fallback
            from app.redis.keys import RedisKeys
            loc_data = await redis.hgetall(RedisKeys.driver_location(driver_uid))
            if loc_data and "latitude" in loc_data and "longitude" in loc_data:
                try:
                    pos = (float(loc_data["longitude"]), float(loc_data["latitude"]))
                except (ValueError, TypeError):
                    pos = None

        if not pos:
            logger.warning("Targeted driver %s has no valid GPS position", driver_uid)
            return None

        lng, lat = pos
        dist_km = haversine_distance_km(request.pickup_lat, request.pickup_lng, lat, lng)
        max_allowed_radius = max(settings.fallback_radius_km, 10.0)
        if dist_km > max_allowed_radius:
            logger.warning(
                "Targeted driver %s is too far away (%.2f km > %.2f km)",
                driver_uid,
                dist_km,
                max_allowed_radius,
            )
            return None

        # 3. Attempt Atomic Reservation Lock (SET NX EX)
        lock_acquired = await acquire_driver_lock(redis, driver_uid, passenger_uid)
        if not lock_acquired:
            logger.warning(
                "Targeted driver %s reservation lock could not be acquired (competitor booking)",
                driver_uid,
            )
            return None

        try:
            # 4. Double check eligibility while holding lock
            if not await is_driver_eligible(redis, driver_uid, ride_id):
                logger.warning("Targeted driver %s became ineligible after locking", driver_uid)
                await release_driver_lock(redis, driver_uid, passenger_uid)
                return None

            logger.info("Successfully reserved targeted driver %s for ride %s", driver_uid, ride_id)
            return driver_uid
        except Exception as e:
            logger.error("Error during targeted reservation for driver %s: %s", driver_uid, e)
            await release_driver_lock(redis, driver_uid, passenger_uid)
            raise

    # ── Path B: Proximity-based Auto-Matching ─────────────────────────────────
    radii = [settings.initial_radius_km, settings.fallback_radius_km]

    for radius in radii:
        logger.debug(f"Searching for drivers within {radius}km of {request.pickup_lat}, {request.pickup_lng}")
        
        # 1. GEO Search (fast candidate generation)
        candidates = await geo_search_drivers(
            redis,
            center_lat=request.pickup_lat,
            center_lng=request.pickup_lng,
            radius_km=radius,
            count=100,
        )
        
        if not candidates:
            continue

        ranked_candidates = []
        for uid, approx_dist in candidates:
            if not await is_driver_eligible(redis, uid, ride_id):
                continue
                
            pos = await geo_get_position(redis, uid)
            if not pos:
                loc_data = await redis.hgetall(RedisKeys.driver_location(uid))
                if loc_data and "latitude" in loc_data and "longitude" in loc_data:
                    try:
                        pos = (float(loc_data["longitude"]), float(loc_data["latitude"]))
                    except (ValueError, TypeError):
                        pos = None
            if not pos:
                continue
            
            lng, lat = pos
            exact_dist = haversine_distance_km(
                request.pickup_lat, request.pickup_lng, lat, lng
            )
            
            if exact_dist <= radius:
                ranked_candidates.append((exact_dist, uid))

        # 2. Sort by exact distance
        ranked_candidates.sort(key=lambda x: x[0])

        # 3. Attempt Atomic Reservation
        for exact_dist, driver_uid in ranked_candidates:
            logger.info("Attempting reservation lock on driver %s (dist: %.2fkm)", driver_uid, exact_dist)
            
            lock_acquired = await acquire_driver_lock(redis, driver_uid, passenger_uid)
            if not lock_acquired:
                logger.debug("Failed to acquire lock for driver %s (competitor got it)", driver_uid)
                continue
                
            try:
                # 4. Double-check eligibility while holding the lock
                if not await is_driver_eligible(redis, driver_uid, ride_id):
                    logger.debug("Driver %s became ineligible during lock acquisition", driver_uid)
                    await release_driver_lock(redis, driver_uid, passenger_uid)
                    continue

                # 5. Success
                logger.info("Successfully reserved driver %s for ride %s", driver_uid, ride_id)
                return driver_uid
                
            except Exception as e:
                logger.error("Error during reservation process for driver %s: %s", driver_uid, e)
                await release_driver_lock(redis, driver_uid, passenger_uid)
                raise
                
    # Exhausted all radii
    logger.info("No eligible drivers found for passenger %s across all search radii", passenger_uid)
    return None
