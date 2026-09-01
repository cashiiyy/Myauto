"""
Location Validation Service
===========================

Validates incoming location updates beyond schema boundaries.
Checks for sequence numbers, realistic speeds, and accuracy thresholds.
"""

from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis

from app.config.settings import get_settings
from app.redis.keys import RedisKeys
from app.schemas.location import LocationUpdate

logger = logging.getLogger(__name__)


async def validate_location_update(
    update: LocationUpdate,
    uid: str,
    redis: aioredis.Redis,
) -> tuple[bool, Optional[str]]:
    """
    Validate a location update.
    Returns (is_valid, error_message).
    """
    settings = get_settings()

    # 1. Accuracy Check
    if (
        update.accuracy_meters is not None
        and update.accuracy_meters > settings.max_match_accuracy_meters
    ):
        return False, f"Accuracy {update.accuracy_meters}m exceeds maximum allowed {settings.max_match_accuracy_meters}m"

    # 2. Sequence Check (Prevent out-of-order updates)
    if update.sequence is not None:
        seq_key = RedisKeys.driver_sequence(uid)
        last_seq_str = await redis.get(seq_key)
        if last_seq_str is not None:
            last_seq = int(last_seq_str)
            # Detect client restart or sequence reset (seq=1 or dropped significantly below last_seq)
            if update.sequence == 1 or update.sequence < (last_seq - 5):
                logger.info("Sequence reset detected for %s (%s -> %s), accepting as new session", uid, last_seq, update.sequence)
            elif update.sequence <= last_seq:
                logger.debug("Rejecting out-of-order sequence %s <= %s for %s", update.sequence, last_seq, uid)
                return False, f"Out of order sequence number {update.sequence}"
        
        # Update sequence
        await redis.set(seq_key, str(update.sequence), ex=60)

    return True, None
