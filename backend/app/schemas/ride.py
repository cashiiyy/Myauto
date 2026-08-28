"""
Pydantic Schemas — Rides
=========================

Request/response schemas for the ride lifecycle API.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


# ── Ride Request ───────────────────────────────────────────────────────────────


class CreateRideRequest(BaseModel):
    """POST /api/rides/requests body."""

    pickup_lat: float = Field(..., ge=-90.0, le=90.0)
    pickup_lng: float = Field(..., ge=-180.0, le=180.0)
    pickup_accuracy_meters: Optional[float] = Field(None, ge=0.0)

    # Destination data
    destination_lat: Optional[float] = Field(None, ge=-90.0, le=90.0)
    destination_lng: Optional[float] = Field(None, ge=-180.0, le=180.0)
    destination_label: Optional[str] = Field(None, max_length=256)

    # Optional: passenger targeted a specific driver
    driver_uid: Optional[str] = Field(None, max_length=128)

    # Optional: passenger name snapshot
    passenger_name: Optional[str] = Field(None, max_length=128)

    # Optional: client-generated idempotency key
    idempotency_key: Optional[str] = Field(None, max_length=64)

    # Optional: notes for the driver (e.g., landmark)
    notes: Optional[str] = Field(None, max_length=256)

    @model_validator(mode="after")
    def validate_destination_completeness(self) -> CreateRideRequest:
        has_lat = self.destination_lat is not None
        has_lng = self.destination_lng is not None
        if has_lat != has_lng:
            raise ValueError("Both destination_lat and destination_lng must be provided together.")
        return self


class RideRequestResponse(BaseModel):
    """Response after creating a ride request."""

    request_id: str  # UUID as string
    status: str
    message: str
    driver_uid: Optional[str] = None
    created_at: datetime


# ── Match Actions ──────────────────────────────────────────────────────────────


class MatchActionResponse(BaseModel):
    """Response after accept/reject of a match."""

    match_id: str  # ride/match ID — string to avoid UUID conversion errors from path params
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
