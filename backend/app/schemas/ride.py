"""
Pydantic Schemas — Rides
=========================

Request/response schemas for the ride lifecycle API.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


# ── Ride Request ───────────────────────────────────────────────────────────────


class CreateRideRequest(BaseModel):
    """POST /api/ride-requests body."""

    pickup_lat: float = Field(..., ge=-90.0, le=90.0)
    pickup_lng: float = Field(..., ge=-180.0, le=180.0)
    pickup_accuracy_meters: Optional[float] = Field(None, ge=0.0)
    # Optional: notes for the driver (e.g., landmark)
    notes: Optional[str] = Field(None, max_length=256)


class RideRequestResponse(BaseModel):
    """Response after creating a ride request."""

    request_id: UUID
    status: str
    message: str
    created_at: datetime


# ── Match Actions ──────────────────────────────────────────────────────────────


class MatchActionResponse(BaseModel):
    """Response after accept/reject of a match."""

    match_id: UUID
    status: str
    message: str


# ── Ride Session ───────────────────────────────────────────────────────────────


class RideSessionResponse(BaseModel):
    """Response for ride session state."""

    session_id: UUID
    match_id: UUID
    state: str
    started_at: datetime
    completed_at: Optional[datetime] = None


# ── SOS ───────────────────────────────────────────────────────────────────────


class SOSRequest(BaseModel):
    """POST /api/rides/{id}/sos body."""

    latitude: Optional[float] = Field(None, ge=-90.0, le=90.0)
    longitude: Optional[float] = Field(None, ge=-180.0, le=180.0)
    message: Optional[str] = Field(None, max_length=256)


class SOSResponse(BaseModel):
    """Response after SOS is triggered."""

    sos_event_id: UUID
    acknowledged: bool
    message: str
