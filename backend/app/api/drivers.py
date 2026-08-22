"""
Drivers API
===========
"""

from fastapi import APIRouter, Depends
import redis.asyncio as aioredis

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.redis.geo import geo_search_drivers
from app.schemas.driver import NearbyDriverResponse

router = APIRouter(prefix="/api/drivers", tags=["Drivers"])

@router.get("/nearby", response_model=list[NearbyDriverResponse])
async def get_nearby_drivers(
    lat: float,
    lng: float,
    radius_km: float = 2.0,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
):
    candidates = await geo_search_drivers(redis, lat, lng, radius_km)
    
    responses = []
    for uid, dist in candidates:
        responses.append(NearbyDriverResponse(
            driver_uid=uid,
            latitude=lat, # Mock, needs true location lookup from hash
            longitude=lng, # Mock, needs true location lookup from hash
            distance_km=dist,
            freshness="LIVE"
        ))
    return responses
