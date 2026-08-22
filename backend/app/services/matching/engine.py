"""
Nearest Driver Engine
======================

The core algorithm for selecting the best driver for a passenger request.
Enforces atomicity and eligibility.
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
    Find and atomically reserve the nearest eligible driver.
    Returns the driver_uid if successful, None if no driver found.
    """
    settings = get_settings()

    # Define the search rings (e.g. 2km, then 5km)
    radii = [settings.initial_radius_km, settings.fallback_radius_km]

    for radius in radii:
        logger.debug(f"Searching for drivers within {radius}km of {request.pickup_lat}, {request.pickup_lng}")
        
        # 1. GEO Search (fast candidate generation)
        candidates = await geo_search_drivers(
            redis,
            center_lat=request.pickup_lat,
            center_lng=request.pickup_lng,
            radius_km=radius,
            count=100,  # limit to top 100 in radius
        )
        
        if not candidates:
            continue

        # Candidates are returned as (driver_uid, approx_dist) from Redis GEO.
        # We need exact Haversine ranking to match client expectations and filter
        # out ineligible candidates.
        
        ranked_candidates = []
        for uid, approx_dist in candidates:
            if not await is_driver_eligible(redis, uid, ride_id):
                continue
                
            # Get exact lat/lng for accurate Haversine calculation
            pos = await geo_get_position(redis, uid)
            if not pos:
                continue
            
            lng, lat = pos
            exact_dist = haversine_distance_km(
                request.pickup_lat, request.pickup_lng, lat, lng
            )
            
            # Re-check radius with exact distance
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
                # (State could have changed between search and lock acquisition)
                if not await is_driver_eligible(redis, driver_uid, ride_id):
                    logger.debug("Driver %s became ineligible during lock acquisition", driver_uid)
                    await release_driver_lock(redis, driver_uid, passenger_uid)
                    continue

                # 5. Success! The caller is now responsible for DB transactions 
                # and releasing the lock once state is updated.
                logger.info("Successfully reserved driver %s for ride %s", driver_uid, ride_id)
                return driver_uid
                
            except Exception as e:
                logger.error("Error during reservation process for driver %s: %s", driver_uid, e)
                await release_driver_lock(redis, driver_uid, passenger_uid)
                raise
                
    # Exhausted all radii
    logger.info("No eligible drivers found for passenger %s across all search radii", passenger_uid)
    return None
