"""
SQLAlchemy ORM Models — Rides
==============================

Tables:
  ride_requests  — passenger ride requests
  ride_matches   — server-selected driver ↔ passenger pairs
  ride_sessions  — active/completed/cancelled rides
  ride_events    — append-only event log per session
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from geoalchemy2 import Geometry
from sqlalchemy import (
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class RideRequest(Base):
    """
    Passenger's ride request.
    Created when a passenger calls POST /api/ride-requests.
    """

    __tablename__ = "ride_requests"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    passenger_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Pickup location as PostGIS Point (SRID 4326 = WGS84)
    pickup_location: Mapped[object] = mapped_column(
        Geometry("POINT", srid=4326), nullable=False
    )
    pickup_lat: Mapped[float] = mapped_column(Float, nullable=False)
    pickup_lng: Mapped[float] = mapped_column(Float, nullable=False)
    pickup_accuracy_meters: Mapped[float | None] = mapped_column(Float, nullable=True)

    # status: 'requested' | 'matching' | 'reserved' | 'accepted' |
    #         'active' | 'completed' | 'cancelled' | 'rejected' | 'expired'
    status: Mapped[str] = mapped_column(
        Enum(
            "requested",
            "matching",
            "reserved",
            "accepted",
            "active",
            "completed",
            "cancelled",
            "rejected",
            "expired",
            name="ride_status_enum",
        ),
        default="requested",
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )

    # Relationships
    matches: Mapped[list["RideMatch"]] = relationship(
        "RideMatch", back_populates="request", cascade="all, delete-orphan"
    )


class RideMatch(Base):
    """
    Server-selected driver ↔ passenger match.
    Created atomically by the matching engine.
    """

    __tablename__ = "ride_matches"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    request_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("ride_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    driver_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    passenger_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # status: 'pending' | 'accepted' | 'rejected' | 'cancelled'
    status: Mapped[str] = mapped_column(
        Enum(
            "pending",
            "accepted",
            "rejected",
            "cancelled",
            name="match_status_enum",
        ),
        default="pending",
        nullable=False,
    )

    # Distance at time of match (for analytics)
    distance_meters: Mapped[float | None] = mapped_column(Float, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    responded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Relationships
    request: Mapped["RideRequest"] = relationship(
        "RideRequest", back_populates="matches"
    )
    session: Mapped["RideSession | None"] = relationship(
        "RideSession", back_populates="match", uselist=False
    )


class RideSession(Base):
    """
    The live or completed ride session.
    Only participants (selected driver + selected passenger) may access it.
    """

    __tablename__ = "ride_sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    match_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("ride_matches.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    driver_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    passenger_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # state mirrors RideRequest status for active sessions
    state: Mapped[str] = mapped_column(
        Enum(
            "accepted",
            "active",
            "completed",
            "cancelled",
            name="session_state_enum",
        ),
        default="accepted",
        nullable=False,
    )

    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Relationships
    match: Mapped["RideMatch"] = relationship("RideMatch", back_populates="session")
    events: Mapped[list["RideEvent"]] = relationship(
        "RideEvent", back_populates="session", cascade="all, delete-orphan"
    )


class RideEvent(Base):
    """
    Append-only event log for a ride session.
    Every state change, SOS, and contact request is recorded here.
    """

    __tablename__ = "ride_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("ride_sessions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    event_type: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    payload: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )

    # Relationships
    session: Mapped["RideSession"] = relationship("RideSession", back_populates="events")
