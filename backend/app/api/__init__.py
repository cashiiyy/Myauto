"""
Centralised API Router
======================
Aggregates all API route modules.
"""

from fastapi import APIRouter

from app.api.drivers import router as drivers_router
from app.api.geocoding import router as geocoding_router
from app.api.health import router as health_router
from app.api.location import router as location_router
from app.api.matches import router as matches_router
from app.api.rides import router as rides_router
from app.api.routing import router as routing_router

api_router = APIRouter()

api_router.include_router(health_router)
api_router.include_router(geocoding_router)
api_router.include_router(routing_router)
api_router.include_router(location_router)
api_router.include_router(drivers_router)
api_router.include_router(rides_router)
api_router.include_router(matches_router)

__all__ = ["api_router"]
