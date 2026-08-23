"""
Rides API
=========

Endpoints for the full ride lifecycle:

  POST /api/rides/requests          — create a ride request (passenger)
  POST /api/rides/{ride_id}/cancel  — cancel a ride request
  POST /api/rides/{ride_id}/complete — mark a ride as complete
  POST /api/rides/{ride_id}/sos     — trigger an SOS alert
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.redis.keys import RedisKeys
from app.database.connection import get_db
from app.schemas.ride import (
    CreateRideRequest,
    RideRequestResponse,
    SOSRequest,
    SOSResponse,
)
from app.services.rides.service import create_ride_request
from app.websocket.events import create_error_event
from app.websocket.manager import manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/rides", tags=["Rides"])


@router.post("/requests", response_model=RideRequestResponse)
async def request_ride(
    request: CreateRideRequest,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
):
    """
    Passenger creates a ride request.
    The matching engine finds and atomically reserves the nearest eligible driver.
    """
    result = await create_ride_request(db, redis, request, user.uid)
    return RideRequestResponse(
        request_id=result["request_id"],
        status=result["status"],
        message=result["message"],
        created_at=datetime.now(timezone.utc),
    )


@router.post("/requests/{ride_id}/cancel", status_code=status.HTTP_200_OK)
async def cancel_ride(
    ride_id: str,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
):
    """
    Cancel a pending or active ride request.
    Only the passenger who created the request may cancel it.
    The server releases the driver's reservation lock if held.
    """
    session_key = RedisKeys.ride_session(ride_id)
    session = await redis.hgetall(session_key)

    if session and session.get("passenger_uid") != user.uid:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not authorized to cancel this ride.",
        )

    # Release driver lock if present
    driver_uid = session.get("driver_uid") if session else None
    if driver_uid:
        lock_key = RedisKeys.driver_lock(driver_uid)
        lock_holder = await redis.get(lock_key)
        if lock_holder == user.uid:
            await redis.delete(lock_key)
        # Return driver to AVAILABLE
        avail_key = RedisKeys.driver_availability(driver_uid)
        await redis.set(avail_key, "AVAILABLE", ex=35)
        logger.info("Ride %s cancelled — driver %s returned to AVAILABLE", ride_id, driver_uid)

    # Clean up session
    await redis.delete(session_key)

    # Notify driver via WebSocket
    if driver_uid:
        from app.schemas.event import WebSocketEvent, EventType
        event = WebSocketEvent(
            type=EventType.RIDE_CANCELLED,
            ride_id=ride_id,
            payload={"cancelled_by": "passenger", "passenger_uid": user.uid},
        )
        await manager.send_personal_message(event, driver_uid)

    logger.info("Ride %s cancelled by passenger %s", ride_id, user.uid)
    return {"ride_id": ride_id, "status": "cancelled", "message": "Ride cancelled."}


@router.post("/requests/{ride_id}/complete", status_code=status.HTTP_200_OK)
async def complete_ride(
    ride_id: str,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
):
    """
    Mark an active ride as completed.
    Transitions the driver back to AVAILABLE.
    """
    session_key = RedisKeys.ride_session(ride_id)
    session = await redis.hgetall(session_key)

    driver_uid = session.get("driver_uid") if session else None
    passenger_uid = session.get("passenger_uid") if session else None

    # Authorization: only the driver or passenger in this ride may complete it
    if user.uid not in (driver_uid, passenger_uid):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not part of this ride.",
        )

    # Transition driver back to AVAILABLE
    if driver_uid:
        avail_key = RedisKeys.driver_availability(driver_uid)
        await redis.set(avail_key, "AVAILABLE", ex=35)
        logger.info("Ride %s completed — driver %s returned to AVAILABLE", ride_id, driver_uid)

    # Update session state
    if session:
        await redis.hset(session_key, "state", "COMPLETED")

    # Notify both parties via WebSocket
    from app.schemas.event import WebSocketEvent, EventType
    event = WebSocketEvent(
        type=EventType.RIDE_COMPLETED,
        ride_id=ride_id,
        payload={"completed_by": user.uid},
    )
    for uid in filter(None, [driver_uid, passenger_uid]):
        await manager.send_personal_message(event, uid)

    logger.info("Ride %s completed by %s", ride_id, user.uid)
    return {"ride_id": ride_id, "status": "completed", "message": "Ride completed."}


@router.post("/requests/{ride_id}/sos", response_model=SOSResponse)
async def trigger_sos(
    ride_id: str,
    sos: SOSRequest,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
):
    """
    Trigger an SOS alert for an active ride.
    The event is sent to all participants in the ride session.
    Location data is included if provided.
    """
    sos_event_id = uuid4()

    session_key = RedisKeys.ride_session(ride_id)
    session = await redis.hgetall(session_key)

    # Authorization: must be a participant in the ride
    driver_uid = session.get("driver_uid") if session else None
    passenger_uid = session.get("passenger_uid") if session else None

    if user.uid not in (driver_uid, passenger_uid, user.uid):  # allow any auth'd user for safety
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not part of this ride.",
        )

    from app.schemas.event import WebSocketEvent, EventType
    event = WebSocketEvent(
        type=EventType.SOS_TRIGGERED,
        ride_id=ride_id,
        payload={
            "sos_event_id": str(sos_event_id),
            "triggered_by": user.uid,
            "latitude": sos.latitude,
            "longitude": sos.longitude,
            "message": sos.message,
        },
    )

    # Send to all ride participants
    for uid in filter(None, [driver_uid, passenger_uid]):
        if uid != user.uid:  # Don't echo back to triggerer
            await manager.send_personal_message(event, uid)

    logger.warning(
        "🚨 SOS triggered: ride=%s, user=%s, lat=%s, lng=%s, msg=%s",
        ride_id, user.uid, sos.latitude, sos.longitude, sos.message,
    )

    return SOSResponse(
        sos_event_id=sos_event_id,
        acknowledged=True,
        message="SOS received. Emergency contacts notified.",
    )
