"""
Pydantic Schemas — Drivers
===========================

Response schemas for nearby-driver queries.
Phone numbers are NEVER included in any of these schemas.
"""

from __future__ import annotations

from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


class NearbyDriverResponse(BaseModel):
    """
    Public driver data returned by GET /api/drivers/nearby.
    Contains no sensitive information (no phone, no internal IDs beyond uid).
    """

    driver_uid: str = Field(..., description="Firebase UID of the driver")
    latitude: float
    longitude: float
    distance_km: float = Field(..., description="Distance from the requesting passenger")
    heading_degrees: Optional[float] = None
    accuracy_meters: Optional[float] = None
    freshness: str = Field(..., description="LIVE | DELAYED | STALE")
    # Vehicle display info only — no license plate PII in Phase 1
    vehicle_type: str = "auto-rickshaw"
    rating: Optional[float] = None
    is_available: bool = True


class DriverPresenceEvent(BaseModel):
    """Internal driver presence data used by the matching engine. Not sent to clients."""

    driver_uid: str
    latitude: float
    longitude: float
    accuracy_meters: Optional[float] = None
    speed_mps: Optional[float] = None
    heading_degrees: Optional[float] = None
    freshness: str
    driver_state: str  # OFFLINE | AVAILABLE | CONTACTED | RESERVED | BUSY | STALE
    last_seen_at: int  # Unix ms
    sequence: Optional[int] = None
