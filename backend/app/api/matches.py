"""
Matches API
===========

POST /api/matches/{match_id}/accept — driver accepts a match
POST /api/matches/{match_id}/reject — driver rejects a match
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.redis.keys import RedisKeys
from app.database.connection import get_db
from app.repositories.ride_repository import RideRepository
from app.schemas.ride import MatchActionResponse
from app.websocket.manager import manager
from app.schemas.event import WebSocketEvent, EventType

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/matches", tags=["Matches"])


@router.post("/{match_id}/accept", response_model=MatchActionResponse)
async def accept_match(
    match_id: str,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
):
    """
    Driver accepts a ride request match.
    Validates expiration, transitions the ride session to ACTIVE, updates DB, and notifies the passenger.
    """
    session_key = RedisKeys.ride_session(match_id)
    session = await redis.hgetall(session_key)

    driver_uid = session.get("driver_uid") if session else None
    passenger_uid = session.get("passenger_uid") if session else None
    expires_at_str = session.get("expires_at") if session else None

    # Check expiration
    if expires_at_str:
        try:
            expires_at = datetime.fromisoformat(expires_at_str)
            if datetime.now(timezone.utc) > expires_at:
                # Return driver to AVAILABLE
                avail_key = RedisKeys.driver_availability(user.uid)
                await redis.set(avail_key, "AVAILABLE", ex=35)

                # Notify passenger
                if passenger_uid:
                    event = WebSocketEvent(
                        type=EventType.RIDE_REJECTED,
                        ride_id=match_id,
                        payload={"message": "Ride request expired."},
                    )
                    await manager.send_personal_message(event, passenger_uid)

                raise HTTPException(
                    status_code=status.HTTP_410_GONE,
                    detail="This ride request has expired.",
                )
        except HTTPException:
            raise
        except Exception as e:
            logger.debug("Expiry check parse error: %s", e)

    # Authorization: only the reserved driver may accept
    if driver_uid and driver_uid != user.uid:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the assigned driver may accept this match.",
        )

    # Transition driver state to BUSY
    avail_key = RedisKeys.driver_availability(user.uid)
    await redis.set(avail_key, "BUSY", ex=3600)

    # Update session state
    if session:
        await redis.hset(session_key, "state", "ACTIVE")

    # Update PostgreSQL
    try:
        ride_repo = RideRepository(db)
        await ride_repo.update_status(
            ride_id=UUID(match_id),
            status="accepted",
            driver_uid=user.uid,
        )
        await db.commit()
    except Exception as db_err:
        logger.debug("DB status update error on accept: %s", db_err)
        await db.rollback()

    # Notify passenger
    if passenger_uid:
        event = WebSocketEvent(
            type=EventType.RIDE_ACCEPTED,
            ride_id=match_id,
            payload={
                "driver_uid": user.uid,
                "match_id": match_id,
            },
        )
        await manager.send_personal_message(event, passenger_uid)
        logger.info("Ride %s accepted by driver %s — passenger %s notified", match_id, user.uid, passenger_uid)

    return MatchActionResponse(
        match_id=match_id,
        status="accepted",
        message="Match accepted. Your ride is confirmed.",
    )


@router.post("/{match_id}/reject", response_model=MatchActionResponse)
async def reject_match(
    match_id: str,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
):
    """
    Driver rejects a ride request match.
    Records rejection, returns driver to AVAILABLE, updates DB, and notifies passenger.
    """
    session_key = RedisKeys.ride_session(match_id)
    session = await redis.hgetall(session_key)

    passenger_uid = session.get("passenger_uid") if session else None

    # Add this driver to the rejected set for this ride
    rejected_key = RedisKeys.ride_rejected(match_id)
    await redis.sadd(rejected_key, user.uid)
    await redis.expire(rejected_key, 600)

    # Release driver's lock and return to AVAILABLE
    lock_key = RedisKeys.driver_lock(user.uid)
    await redis.delete(lock_key)
    avail_key = RedisKeys.driver_availability(user.uid)
    await redis.set(avail_key, "AVAILABLE", ex=35)

    # Update session state back to SEARCHING
    if session:
        await redis.hset(session_key, mapping={"state": "SEARCHING", "driver_uid": ""})

    # Update PostgreSQL status
    try:
        ride_repo = RideRepository(db)
        await ride_repo.update_status(
            ride_id=UUID(match_id),
            status="rejected",
            cancelled_by="driver",
            cancel_reason=f"Rejected by driver {user.uid}",
        )
        await db.commit()
    except Exception as db_err:
        logger.debug("DB status update error on reject: %s", db_err)
        await db.rollback()

    # Notify passenger that driver rejected
    if passenger_uid:
        event = WebSocketEvent(
            type=EventType.RIDE_REJECTED,
            ride_id=match_id,
            payload={
                "rejected_by_driver": user.uid,
                "message": "Driver declined. Looking for another driver...",
            },
        )
        await manager.send_personal_message(event, passenger_uid)
        logger.info("Ride %s rejected by driver %s — passenger %s notified", match_id, user.uid, passenger_uid)

    return MatchActionResponse(
        match_id=match_id,
        status="rejected",
        message="Match rejected. Looking for next available driver.",
    )
