"""
Atomic Redis Locks.

Used to prevent race conditions, notably when two passengers attempt
to reserve the same driver simultaneously.
"""

from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis

from app.config.settings import get_settings
from app.redis.keys import RedisKeys

logger = logging.getLogger(__name__)


async def acquire_driver_lock(
    redis: aioredis.Redis,
    driver_uid: str,
    passenger_uid: str,
) -> bool:
    """
    Attempt to acquire a reservation lock on a driver.

    Uses Redis SET NX EX to ensure atomicity. Only one passenger can
    acquire this lock at a time. The lock automatically expires.
    """
    settings = get_settings()
    key = RedisKeys.driver_lock(driver_uid)
    
    # SET key value NX EX ttl
    result = await redis.set(
        key,
        passenger_uid,
        ex=settings.driver_lock_ttl_seconds,
        nx=True,
    )
    
    return bool(result)


async def release_driver_lock(
    redis: aioredis.Redis,
    driver_uid: str,
    passenger_uid: str,
) -> bool:
    """
    Release a driver lock.
    Uses a Lua script to ensure we only delete the lock if we own it.
    """
    key = RedisKeys.driver_lock(driver_uid)
    
    # Lua script: if GET key == passenger_uid then DEL key else 0
    script = """
    if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
    else
        return 0
    end
    """
    
    try:
        result = await redis.eval(script, 1, key, passenger_uid)
        return bool(result)
    except Exception:
        current = await redis.get(key)
        if current == passenger_uid:
            await redis.delete(key)
            return True
        return False
