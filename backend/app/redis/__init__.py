# backend/app/redis/__init__.py
from .client import close_redis, get_redis, init_redis
from .geo import geo_add_driver, geo_get_position, geo_remove_driver, geo_search_drivers
from .keys import RedisKeys
from .locks import acquire_driver_lock, release_driver_lock
from .presence import (
    get_driver_availability,
    get_driver_presence,
    refresh_driver_ttl,
    remove_driver_presence,
    set_driver_availability,
    set_driver_presence,
)

__all__ = [
    "RedisKeys",
    "acquire_driver_lock",
    "close_redis",
    "geo_add_driver",
    "geo_get_position",
    "geo_remove_driver",
    "geo_search_drivers",
    "get_driver_availability",
    "get_driver_presence",
    "get_redis",
    "init_redis",
    "refresh_driver_ttl",
    "release_driver_lock",
    "remove_driver_presence",
    "set_driver_availability",
    "set_driver_presence",
]
