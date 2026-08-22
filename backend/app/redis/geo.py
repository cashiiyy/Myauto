"""
Redis GEO helpers — driver spatial indexing.

Uses Redis GEO commands (backed by a sorted set) to store and query
active driver locations.  This provides fast O(N+log(M)) radius searches
without full table scans.

All coordinates are stored as (longitude, latitude) — the Redis GEO
convention (opposite of most geography APIs).
"""

from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis

from app.redis.keys import RedisKeys

logger = logging.getLogger(__name__)


async def geo_add_driver(
    redis: aioredis.Redis,
    driver_uid: str,
    latitude: float,
    longitude: float,
) -> None:
    """
    Add or update a driver's position in the GEO sorted set.
    Redis GEO convention: GEOADD key longitude latitude member
    """
    await redis.geoadd(
        RedisKeys.DRIVERS_GEO,
        [longitude, latitude, driver_uid],
    )


async def geo_remove_driver(
    redis: aioredis.Redis,
    driver_uid: str,
) -> None:
    """Remove a driver from the GEO sorted set (e.g., when they go offline)."""
    await redis.zrem(RedisKeys.DRIVERS_GEO, driver_uid)


async def geo_search_drivers(
    redis: aioredis.Redis,
    center_lat: float,
    center_lng: float,
    radius_km: float,
    count: int = 50,
) -> list[tuple[str, float]]:
    """
    Find drivers within radius_km of (center_lat, center_lng).

    Returns a list of (driver_uid, distance_km) tuples sorted by distance.
    """
    try:
        results = await redis.geosearch(
            RedisKeys.DRIVERS_GEO,
            longitude=center_lng,
            latitude=center_lat,
            radius=radius_km,
            unit="km",
            sort="ASC",
            count=count,
            withcoord=False,
            withdist=True,
        )
        # results: list of [member, distance_str]
        return [
            (item[0], float(item[1]))
            for item in (results or [])
        ]
    except Exception as exc:
        logger.error("geo_search_drivers failed: %s", exc)
        return []


async def geo_get_position(
    redis: aioredis.Redis,
    driver_uid: str,
) -> Optional[tuple[float, float]]:
    """
    Return the (longitude, latitude) stored in the GEO index for a driver.
    Returns None if the driver is not in the index.
    Note: GEO precision is approximately ±0.6mm — sufficient for matching.
    """
    positions = await redis.geopos(RedisKeys.DRIVERS_GEO, driver_uid)
    if positions and positions[0] is not None:
        lng, lat = positions[0]
        return float(lng), float(lat)
    return None
