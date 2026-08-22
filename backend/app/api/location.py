"""
Location API
============
"""

from fastapi import APIRouter, Depends, status
import redis.asyncio as aioredis

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.schemas.location import LocationUpdate, LocationResponse
from app.services.location.service import process_driver_location, process_passenger_location
# from app.models.user import User  # Would be used to determine role

router = APIRouter(prefix="/api/location", tags=["Location"])

@router.post("", response_model=LocationResponse, status_code=status.HTTP_200_OK)
async def update_location(
    update: LocationUpdate,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    # db: AsyncSession = Depends(get_db)
):
    # For Phase 1 without DB wiring in this mock, we assume driver if not specified
    # Real implementation: role = get_user_role(db, user.uid)
    role = "driver" 
    
    try:
        if role == "driver":
            stored = await process_driver_location(update, user.uid, redis)
        else:
            stored = await process_passenger_location(update, user.uid, redis)
            
        return LocationResponse(
            accepted=True,
            freshness=stored.freshness,
            server_timestamp=stored.received_at, # This should be a datetime, casting later
            message="Location updated"
        )
    except ValueError as e:
        return LocationResponse(
            accepted=False,
            freshness="OFFLINE",
            server_timestamp=0, # Need datetime here
            message=str(e)
        )
