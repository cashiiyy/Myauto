"""
Driver Eligibility Checker
==========================

Determines if a driver is a valid candidate for a ride request based on:
- Verification status
- Current state (must be AVAILABLE)
- Location freshness (must be LIVE or DELAYED)
- GPS accuracy
- Rejection history for this ride
"""

from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis

from app.config.settings import get_settings
from app.redis.keys import RedisKeys
from app.schemas.location import StoredLocation

logger = logging.getLogger(__name__)


async def is_driver_eligible(
    redis: aioredis.Redis,
    driver_uid: str,
    ride_id: str,
) -> bool:
    """
    Check if a driver is currently eligible to receive a ride request.
    This check must be FAST. Most state is in Redis.
    """
    settings = get_settings()

    # 1. State must be AVAILABLE
    availability_key = RedisKeys.driver_availability(driver_uid)
    state = await redis.get(availability_key)
    if state != "AVAILABLE":
        logger.debug("Driver %s ineligible: state is %s", driver_uid, state)
        return False

    # 2. Must not have rejected this ride already
    rejected_key = RedisKeys.ride_rejected(ride_id)
    has_rejected = await redis.sismember(rejected_key, driver_uid)
    if has_rejected:
        logger.debug("Driver %s ineligible: already rejected ride %s", driver_uid, ride_id)
        return False

    # 3. Location data checks
    location_key = RedisKeys.driver_location(driver_uid)
    location_data = await redis.hgetall(location_key)
    
    if not location_data:
        logger.debug("Driver %s ineligible: no recent location data", driver_uid)
        return False

    freshness = location_data.get("freshness")
    if freshness not in ("LIVE", "DELAYED"):
        logger.debug("Driver %s ineligible: location is %s", driver_uid, freshness)
        return False

    accuracy_str = location_data.get("accuracy_meters")
    if accuracy_str and accuracy_str != "None":
        accuracy = float(accuracy_str)
        if accuracy > settings.max_match_accuracy_meters:
            logger.debug("Driver %s ineligible: poor accuracy %sm", driver_uid, accuracy)
            return False

    # Verification status is typically checked at connection time or via a DB 
    # check during the final lock acquisition, so we don't query Postgres here 
    # for every candidate in the radius to keep this fast.

    return True
