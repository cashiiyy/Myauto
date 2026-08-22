"""
SQLAlchemy ORM Models — Users and Drivers
==========================================

Tables:
  users               — canonical user records (Firebase uid → internal uuid)
  drivers             — driver-specific profile
  driver_verification — document submission for verification workflow
  vehicles            — vehicle details linked to a driver
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Numeric,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    """
    Canonical user record.
    One row per Firebase UID.
    Role assignment lives here — the client NEVER dictates role.
    """

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    firebase_uid: Mapped[str] = mapped_column(
        String(128), unique=True, nullable=False, index=True
    )
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    # role: 'passenger' | 'driver'
    role: Mapped[str] = mapped_column(
        Enum("passenger", "driver", name="user_role_enum"), nullable=False
    )
    name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Phone is stored here ONLY — never exposed in public events
    phone: Mapped[str | None] = mapped_column(String(30), nullable=True)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_blocked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )

    # Relationships
    driver_profile: Mapped["Driver | None"] = relationship(
        "Driver", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<User uid={self.firebase_uid} role={self.role}>"


class Driver(Base):
    """
    Driver profile.  A User with role='driver' has exactly one Driver row.
    Verification and eligibility state lives here.
    """

    __tablename__ = "drivers"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # verification_status: 'pending' | 'approved' | 'rejected'
    verification_status: Mapped[str] = mapped_column(
        Enum("pending", "approved", "rejected", name="verification_status_enum"),
        default="pending",
        nullable=False,
    )
    rating: Mapped[float] = mapped_column(Numeric(3, 2), default=5.0, nullable=False)
    total_rides: Mapped[int] = mapped_column(default=0, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="driver_profile")
    verifications: Mapped[list["DriverVerification"]] = relationship(
        "DriverVerification", back_populates="driver", cascade="all, delete-orphan"
    )
    vehicles: Mapped[list["Vehicle"]] = relationship(
        "Vehicle", back_populates="driver", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Driver id={self.id} verified={self.is_verified}>"


class DriverVerification(Base):
    """Document/photo submission for a driver verification workflow."""

    __tablename__ = "driver_verification"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    driver_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("drivers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    license_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
    vehicle_registration: Mapped[str | None] = mapped_column(String(30), nullable=True)
    license_photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    vehicle_photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    submitted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    reviewer_notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Relationships
    driver: Mapped["Driver"] = relationship("Driver", back_populates="verifications")


class Vehicle(Base):
    """Vehicle details linked to a driver."""

    __tablename__ = "vehicles"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    driver_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("drivers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    registration_number: Mapped[str] = mapped_column(String(30), nullable=False)
    make: Mapped[str | None] = mapped_column(String(100), nullable=True)
    model: Mapped[str | None] = mapped_column(String(100), nullable=True)
    color: Mapped[str | None] = mapped_column(String(50), nullable=True)
    year: Mapped[int | None] = mapped_column(nullable=True)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    # Relationships
    driver: Mapped["Driver"] = relationship("Driver", back_populates="vehicles")
