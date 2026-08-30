"""
Drivers API
===========

GET /api/drivers/nearby — returns nearby drivers with their actual stored
coordinates fetched from the Redis location hash.
"""

import logging
from fastapi import APIRouter, Depends
import redis.asyncio as aioredis

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.redis.geo import geo_search_drivers
from app.redis.keys import RedisKeys
from app.schemas.driver import NearbyDriverResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/drivers", tags=["Drivers"])


@router.get("/nearby", response_model=list[NearbyDriverResponse])
async def get_nearby_drivers(
    lat: float,
    lng: float,
    radius_km: float = 2.0,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
):
    """
    Return nearby available drivers within radius_km of (lat, lng).
    Driver coordinates are fetched from the Redis location hash,
    NOT from the GEO index (GEO precision is ~0.6mm but we store the
    validated, server-received coordinates in the hash).

    Phone numbers are NEVER returned by this endpoint.
    """
    candidates = await geo_search_drivers(redis, lat, lng, radius_km)
    logger.info(
        "[NEARBY DIAG] query_by_uid=%s lat=%.6f lng=%.6f radius_km=%.1f candidates_found=%d",
        user.uid,
        lat,
        lng,
        radius_km,
        len(candidates),
    )

    responses = []
    for uid, dist_km in candidates:
        # Fetch actual stored coordinates from the location hash
        loc_key = RedisKeys.driver_location(uid)
        loc_data = await redis.hgetall(loc_key)

        if not loc_data:
            logger.debug("[NEARBY DIAG] driver_uid=%s excluded: LOCATION_MISSING (no redis hash)", uid)
            continue

        try:
            driver_lat = float(loc_data.get("latitude", 0))
            driver_lng = float(loc_data.get("longitude", 0))
            freshness = loc_data.get("freshness", "STALE")
            heading = loc_data.get("heading_degrees")
            accuracy = loc_data.get("accuracy_meters")
        except (TypeError, ValueError) as exc:
            logger.warning("[NEARBY DIAG] driver_uid=%s excluded: REDIS_DATA_INVALID (%s)", uid, exc)
            continue

        # Skip drivers whose location is too stale to be useful
        if freshness == "OFFLINE":
            logger.debug("[NEARBY DIAG] driver_uid=%s excluded: OFFLINE", uid)
            continue

        # Check availability
        avail_key = RedisKeys.driver_availability(uid)
        driver_state = await redis.get(avail_key)
        is_available = driver_state == "AVAILABLE"

        logger.info(
            "[NEARBY DIAG] driver_uid=%s included: lat=%.6f lng=%.6f dist_km=%.2f freshness=%s state=%s",
            uid,
            driver_lat,
            driver_lng,
            dist_km,
            freshness,
            driver_state,
        )

        responses.append(NearbyDriverResponse(
            driver_uid=uid,
            latitude=driver_lat,
            longitude=driver_lng,
            distance_km=dist_km,
            heading_degrees=float(heading) if heading else None,
            accuracy_meters=float(accuracy) if accuracy else None,
            freshness=freshness,
            is_available=is_available,
        ))

    logger.info("[NEARBY DIAG] returned_count=%d", len(responses))
    return responses
