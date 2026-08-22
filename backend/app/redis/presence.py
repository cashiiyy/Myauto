"""
Redis Presence — driver online/offline state management.

Manages two Redis structures per driver:
  driver:presence:{uid}     — hash with state and last-seen timestamp
  driver:availability:{uid} — string with the driver's availability state

Both have TTLs so stale drivers expire automatically even if the server
misses a disconnect event.
"""

from __future__ import annotations

import logging
import time
from typing import Optional

import redis.asyncio as aioredis

from app.config.settings import get_settings
from app.redis.keys import RedisKeys

logger = logging.getLogger(__name__)


async def set_driver_presence(
    redis: aioredis.Redis,
    driver_uid: str,
    state: str,
    connection_id: Optional[str] = None,
) -> None:
    """
    Upsert driver presence record with TTL.
    Called every time a location update is received or state changes.
    """
    settings = get_settings()
    now_ms = int(time.time() * 1000)
    key = RedisKeys.driver_presence(driver_uid)

    mapping: dict = {
        "state": state,
        "last_seen_ms": str(now_ms),
    }
    if connection_id:
        mapping["connection_id"] = connection_id

    pipe = redis.pipeline()
    pipe.hset(key, mapping=mapping)
    pipe.expire(key, settings.driver_presence_ttl_seconds)
    await pipe.execute()


async def get_driver_presence(
    redis: aioredis.Redis,
    driver_uid: str,
) -> Optional[dict]:
    """Return the presence hash for a driver, or None if not found/expired."""
    key = RedisKeys.driver_presence(driver_uid)
    data = await redis.hgetall(key)
    return data if data else None


async def remove_driver_presence(
    redis: aioredis.Redis,
    driver_uid: str,
) -> None:
    """Remove a driver from presence records (e.g., explicit logout)."""
    key = RedisKeys.driver_presence(driver_uid)
    await redis.delete(key)


async def set_driver_availability(
    redis: aioredis.Redis,
    driver_uid: str,
    state: str,
) -> None:
    """
    Set the driver's current availability/state with TTL.
    State values: OFFLINE | AVAILABLE | CONTACTED | RESERVED | BUSY | STALE
    """
    settings = get_settings()
    key = RedisKeys.driver_availability(driver_uid)
    await redis.set(key, state, ex=settings.driver_presence_ttl_seconds)


async def get_driver_availability(
    redis: aioredis.Redis,
    driver_uid: str,
) -> Optional[str]:
    """Return driver's current state string, or None if expired/absent."""
    key = RedisKeys.driver_availability(driver_uid)
    return await redis.get(key)


async def refresh_driver_ttl(
    redis: aioredis.Redis,
    driver_uid: str,
) -> None:
    """
    Extend TTLs on all driver keys.
    Called on every successful location update to keep keys alive.
    """
    settings = get_settings()
    pipe = redis.pipeline()
    pipe.expire(RedisKeys.driver_presence(driver_uid), settings.driver_presence_ttl_seconds)
    pipe.expire(RedisKeys.driver_location(driver_uid), settings.live_location_ttl_seconds)
    pipe.expire(RedisKeys.driver_availability(driver_uid), settings.driver_presence_ttl_seconds)
    await pipe.execute()
