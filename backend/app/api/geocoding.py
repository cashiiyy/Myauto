"""
Geocoding API (Photon Integration)
==================================
Exposes search endpoint for passenger destination search.
Does NOT affect or alter existing driver matching logic.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, HTTPException, Query, status

from app.services.photon_service import PhotonService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/geocode", tags=["Geocoding"])
_photon_service = PhotonService()


@router.get("/search", response_model=List[Dict[str, Any]])
async def search_places(
    q: str = Query(..., description="Place name, street, or address to search"),
    limit: int = Query(5, ge=1, le=15, description="Maximum number of results"),
    lat: Optional[float] = Query(None, description="Optional latitude for bias"),
    lon: Optional[float] = Query(None, description="Optional longitude for bias"),
    bbox: Optional[str] = Query(None, description="Optional bounding box bias minLon,minLat,maxLon,maxLat"),
) -> List[Dict[str, Any]]:
    """
    Search places using Photon geocoding engine.
    Returns a safe, standardized list of places.
    """
    trimmed = q.strip()
    if not trimmed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Search query 'q' cannot be empty.",
        )

    try:
        results = await _photon_service.search(
            query=trimmed,
            limit=limit,
            lat=lat,
            lon=lon,
            bbox=bbox,
        )
        return results
    except Exception as e:
        logger.error("Unexpected error in geocoding search: %s", e)
        # Return empty list on failure — never expose internal stack trace
        return []
