"""
Location API
============

POST /api/location — accepts GPS updates from both drivers and passengers.
Role is determined from the request body (drivers send role="driver").
In production this should always be fetched from the DB; for the prototype
we accept it from the body but validate it against the verified token.
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, status
import redis.asyncio as aioredis

from app.auth.firebase_auth import VerifiedToken, get_current_user
from app.redis.client import get_redis
from app.schemas.location import LocationUpdate, LocationResponse, LocationUpdateWithRole
from app.services.location.service import process_driver_location, process_passenger_location

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/location", tags=["Location"])


@router.post("", response_model=LocationResponse, status_code=status.HTTP_200_OK)
async def update_location(
    update: LocationUpdateWithRole,
    user: VerifiedToken = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
):
    """
    Accept a location update from a driver or passenger.

    Body must include ``role`` field: ``"driver"`` or ``"passenger"``.

    The server assigns ``receivedAt`` and ``serverTimestamp`` — the client
    timestamp is only used for freshness classification, never as authority.
    """
    try:
        if update.role == "driver":
            stored = await process_driver_location(update, user.uid, redis)
        else:
            stored = await process_passenger_location(update, user.uid, redis)

        logger.info(
            "[LOCATION DIAG] role=%s uid=%s lat=%.6f lng=%.6f freshness=%s seq=%s saved_to_redis=True",
            update.role,
            user.uid,
            update.latitude,
            update.longitude,
            stored.freshness,
            update.sequence,
        )

        server_ts = datetime.fromtimestamp(stored.received_at / 1000.0, tz=timezone.utc)
        return LocationResponse(
            accepted=True,
            freshness=stored.freshness,
            server_timestamp=server_ts,
            message="Location updated",
        )
    except ValueError as e:
        logger.warning(
            "[LOCATION DIAG] role=%s uid=%s update_rejected: %s",
            update.role,
            user.uid,
            e,
        )
        return LocationResponse(
            accepted=False,
            freshness="OFFLINE",
            server_timestamp=datetime.now(timezone.utc),
            message=str(e),
        )
