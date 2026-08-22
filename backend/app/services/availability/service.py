"""
Availability Service
====================

High-level functions to manage driver state safely.
Coordinates state transitions, Redis updates, and GEO index management.
"""

from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis

from app.redis.geo import geo_remove_driver
from app.redis.presence import (
    get_driver_availability,
    remove_driver_presence,
    set_driver_availability,
)
from app.services.availability.state_machine import validate_transition

logger = logging.getLogger(__name__)


async def update_driver_state(
    redis: aioredis.Redis,
    driver_uid: str,
    new_state: str,
) -> None:
    """
    Safely transition a driver to a new state.
    """
    current_state = await get_driver_availability(redis, driver_uid)
    if current_state is None:
        current_state = "OFFLINE"

    validate_transition(current_state, new_state)

    if new_state == "OFFLINE":
        # Cleanup
        await remove_driver_presence(redis, driver_uid)
        await geo_remove_driver(redis, driver_uid)
        await redis.delete(f"driver:availability:{driver_uid}")
        await redis.delete(f"driver:location:{driver_uid}")
        logger.info("Driver %s went OFFLINE, cleaned up state", driver_uid)
    else:
        await set_driver_availability(redis, driver_uid, new_state)
        logger.info("Driver %s transitioned: %s -> %s", driver_uid, current_state, new_state)


async def handle_stale_driver(
    redis: aioredis.Redis,
    driver_uid: str,
) -> None:
    """
    Called periodically or via key-space notifications when a driver
    fails to send GPS updates.
    Transitions AVAILABLE -> STALE.
    """
    current_state = await get_driver_availability(redis, driver_uid)
    if current_state == "AVAILABLE":
        try:
            await update_driver_state(redis, driver_uid, "STALE")
            # In a full implementation, this might also trigger a WebSocket broadcast
            # to inform passengers that the driver is no longer active.
        except Exception as e:
            logger.error("Failed to mark driver %s as STALE: %s", driver_uid, e)
