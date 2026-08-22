"""
Matches API
===========
"""

from fastapi import APIRouter, Depends
import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.database.connection import get_db
from app.schemas.ride import MatchActionResponse

router = APIRouter(prefix="/api/matches", tags=["Matches"])

@router.post("/{match_id}/accept", response_model=MatchActionResponse)
async def accept_match(
    match_id: str,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db)
):
    return MatchActionResponse(
        match_id=match_id,
        status="accepted",
        message="Match accepted"
    )

@router.post("/{match_id}/reject", response_model=MatchActionResponse)
async def reject_match(
    match_id: str,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db)
):
    return MatchActionResponse(
        match_id=match_id,
        status="rejected",
        message="Match rejected"
    )
