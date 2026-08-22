"""
Pydantic Schemas — Location
============================

Validates incoming GPS location updates from both drivers and passengers.
All validation is server-side — the client cannot bypass it.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from app.config.settings import get_settings


class LocationUpdate(BaseModel):
    """
    Incoming GPS location update payload.

    Expected JSON::

        {
          "latitude": 8.5241,
          "longitude": 76.9366,
          "accuracy_meters": 6.2,
          "altitude": 12.5,
          "speed_mps": 8.4,
          "heading_degrees": 142.5,
          "captured_at": 1724330000000,
          "sequence": 1042
        }
    """

    latitude: float = Field(..., ge=-90.0, le=90.0, description="WGS84 latitude")
    longitude: float = Field(..., ge=-180.0, le=180.0, description="WGS84 longitude")
    accuracy_meters: Optional[float] = Field(
        None, ge=0.0, le=10_000.0, description="GPS horizontal accuracy in metres"
    )
    altitude: Optional[float] = Field(None, description="Altitude in metres MSL")
    speed_mps: Optional[float] = Field(
        None, ge=0.0, description="Speed in metres per second"
    )
    heading_degrees: Optional[float] = Field(
        None, ge=0.0, lt=360.0, description="Bearing 0–359.9 degrees"
    )
    captured_at: int = Field(
        ..., description="Unix timestamp in milliseconds when the fix was captured"
    )
    sequence: Optional[int] = Field(
        None, ge=0, description="Monotonically increasing sequence number from the client"
    )

    @field_validator("latitude")
    @classmethod
    def validate_latitude_bounds(cls, v: float) -> float:
        settings = get_settings()
        if not (settings.lat_min <= v <= settings.lat_max):
            raise ValueError(
                f"Latitude {v} is outside the configured India bounds "
                f"[{settings.lat_min}, {settings.lat_max}]"
            )
        return v

    @field_validator("longitude")
    @classmethod
    def validate_longitude_bounds(cls, v: float) -> float:
        settings = get_settings()
        if not (settings.lon_min <= v <= settings.lon_max):
            raise ValueError(
                f"Longitude {v} is outside the configured India bounds "
                f"[{settings.lon_min}, {settings.lon_max}]"
            )
        return v

    @field_validator("captured_at")
    @classmethod
    def validate_timestamp(cls, v: int) -> int:
        """
        Reject timestamps that are in the far future or impossibly old.
        Allows up to 60 seconds of clock skew (future) and
        rejects anything older than 5 minutes (stale fix).
        """
        now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
        skew_ms = 60_000       # 60 seconds future skew tolerance
        max_age_ms = 300_000   # 5 minutes max age for initial submission

        if v > now_ms + skew_ms:
            raise ValueError(
                f"Timestamp {v} is in the future (possible clock skew > 60s)"
            )
        if v < now_ms - max_age_ms:
            raise ValueError(
                f"Timestamp {v} is too old (> 5 minutes). Submit fresh GPS data."
            )
        return v

    @field_validator("speed_mps")
    @classmethod
    def validate_speed(cls, v: Optional[float]) -> Optional[float]:
        if v is None:
            return v
        settings = get_settings()
        if v > settings.max_speed_mps:
            raise ValueError(
                f"Speed {v} m/s exceeds maximum plausible speed "
                f"{settings.max_speed_mps} m/s for an auto-rickshaw"
            )
        return v


class LocationResponse(BaseModel):
    """Server response after processing a location update."""

    accepted: bool
    freshness: str  # LIVE | DELAYED | STALE | OFFLINE
    server_timestamp: datetime
    message: Optional[str] = None


class StoredLocation(BaseModel):
    """
    Internal representation of a stored driver/passenger location.
    Returned by the location service — never exposed directly to clients.
    """

    uid: str
    latitude: float
    longitude: float
    accuracy_meters: Optional[float] = None
    speed_mps: Optional[float] = None
    heading_degrees: Optional[float] = None
    altitude: Optional[float] = None
    captured_at: int  # ms
    received_at: int  # ms — server time
    sequence: Optional[int] = None
    freshness: str = "LIVE"
