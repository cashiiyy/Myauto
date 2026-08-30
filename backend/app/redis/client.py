"""
Redis connection pool — async (aioredis).

The pool is created once at application startup and shared across all
requests.  Use `get_redis()` to obtain a connection from the pool.
"""

from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis

from app.config.settings import get_settings

logger = logging.getLogger(__name__)

_redis_pool: Optional[aioredis.Redis] = None


async def init_redis() -> aioredis.Redis:
    """
    Initialise the Redis connection pool.
    Idempotent — safe to call multiple times (returns cached pool).
    """
    global _redis_pool
    if _redis_pool is not None:
        return _redis_pool

    settings = get_settings()
    _redis_pool = aioredis.from_url(
        settings.redis_url,
        encoding="utf-8",
        decode_responses=True,
        max_connections=50,
        socket_connect_timeout=5,
        health_check_interval=30,
        retry_on_timeout=True,
    )
    # Verify connectivity
    await _redis_pool.ping()
    logger.info("[REDIS DIAG] connected=True redis_url=%s", settings.redis_url)
    return _redis_pool


async def get_redis() -> aioredis.Redis:
    """
    Return the Redis client.
    Raises RuntimeError if init_redis() has not been called.
    """
    if _redis_pool is None:
        raise RuntimeError(
            "Redis pool is not initialised. Call init_redis() at startup."
        )
    return _redis_pool


async def close_redis() -> None:
    """Close the Redis connection pool. Call during application shutdown."""
    global _redis_pool
    if _redis_pool is not None:
        await _redis_pool.aclose()
        _redis_pool = None
        logger.info("Redis connection pool closed.")
