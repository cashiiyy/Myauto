# backend/app/api/__init__.py
from fastapi import APIRouter

from .drivers import router as drivers_router
from .health import router as health_router
from .location import router as location_router
from .matches import router as matches_router
from .rides import router as rides_router

api_router = APIRouter()

api_router.include_router(health_router)
api_router.include_router(location_router)
api_router.include_router(drivers_router)
api_router.include_router(rides_router)
api_router.include_router(matches_router)

__all__ = ["api_router"]
