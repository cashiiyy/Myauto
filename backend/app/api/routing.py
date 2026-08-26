"""
Routing API (Valhalla Integration)
==================================
Optional route and ETA calculation endpoints.
Controlled by ENABLE_VALHALLA feature flag.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional
from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.services.valhalla_service import ValhallaService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/route", tags=["Routing"])
_valhalla_service = ValhallaService()


class RouteRequest(BaseModel):
    from_lat: float = Field(..., description="Origin latitude")
    from_lon: float = Field(..., description="Origin longitude")
    to_lat: float = Field(..., description="Destination latitude")
    to_lon: float = Field(..., description="Destination longitude")
    costing: str = Field("auto", description="Costing profile (auto, motorcycle)")


@router.get("", response_model=Dict[str, Any])
async def calculate_route_get(
    from_lat: float = Query(..., description="Origin latitude"),
    from_lon: float = Query(..., description="Origin longitude"),
    to_lat: float = Query(..., description="Destination latitude"),
    to_lon: float = Query(..., description="Destination longitude"),
    costing: str = Query("auto", description="Costing profile"),
) -> Dict[str, Any]:
    """Calculate route via GET parameters."""
    return await _calculate(from_lat, from_lon, to_lat, to_lon, costing)


@router.post("", response_model=Dict[str, Any])
async def calculate_route_post(req: RouteRequest) -> Dict[str, Any]:
    """Calculate route via POST JSON payload."""
    return await _calculate(req.from_lat, req.from_lon, req.to_lat, req.to_lon, req.costing)


async def _calculate(
    from_lat: float,
    from_lon: float,
    to_lat: float,
    to_lon: float,
    costing: str,
) -> Dict[str, Any]:
    settings = get_settings()
    if not settings.enable_valhalla:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Valhalla routing engine is disabled on this server.",
        )

    try:
        route = await _valhalla_service.get_route(
            from_lat=from_lat,
            from_lon=from_lon,
            to_lat=to_lat,
            to_lon=to_lon,
            costing=costing,
        )
        if not route:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Unable to calculate route from routing provider.",
            )
        return route
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Error during route calculation: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Route calculation failed.",
        )
