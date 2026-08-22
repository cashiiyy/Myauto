"""
Rides API
=========
"""

from fastapi import APIRouter, Depends
import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.database.connection import get_db
from app.schemas.ride import CreateRideRequest, RideRequestResponse
from app.services.rides.service import create_ride_request

router = APIRouter(prefix="/api/rides", tags=["Rides"])

@router.post("/requests", response_model=RideRequestResponse)
async def request_ride(
    request: CreateRideRequest,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db)
):
    result = await create_ride_request(db, redis, request, user.uid)
    return RideRequestResponse(
        request_id=result["request_id"],
        status=result["status"],
        message=result["message"],
        created_at="2024-08-22T00:00:00Z" # Mock
    )
