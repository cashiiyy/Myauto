"""
SQLAlchemy ORM Models
=====================
PostGIS-enabled database entities for MyAuto.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from geoalchemy2 import Geography
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.session import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    """Passenger or Driver user profile."""
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    firebase_uid = Column(String(128), unique=True, nullable=False, index=True)
    role = Column(String(32), nullable=False, default="passenger")  # passenger, driver
    name = Column(String(128), nullable=True)
    phone = Column(String(32), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    driver_profile = relationship("Driver", back_populates="user", uselist=False, cascade="all, delete-orphan")
    rides_as_passenger = relationship("Ride", back_populates="passenger", foreign_keys="Ride.passenger_uid")
    destinations = relationship("Destination", back_populates="user", cascade="all, delete-orphan")


class Driver(Base):
    """Driver-specific profile & license details."""
    __tablename__ = "drivers"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    driver_uid = Column(String(128), ForeignKey("users.firebase_uid", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    license_number = Column(String(64), nullable=True)
    is_verified = Column(Boolean, default=False, nullable=False)
    rating = Column(Float, default=5.0, nullable=False)
    total_trips = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User", back_populates="driver_profile")
    vehicles = relationship("Vehicle", back_populates="driver", cascade="all, delete-orphan")
    location = relationship("DriverLocation", back_populates="driver", uselist=False, cascade="all, delete-orphan")
    rides = relationship("Ride", back_populates="driver", foreign_keys="Ride.driver_uid")


class Vehicle(Base):
    """Auto-rickshaw vehicle details."""
    __tablename__ = "vehicles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    driver_uid = Column(String(128), ForeignKey("drivers.driver_uid", ondelete="CASCADE"), nullable=False, index=True)
    vehicle_number = Column(String(32), nullable=False)
    model = Column(String(64), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    driver = relationship("Driver", back_populates="vehicles")


class DriverLocation(Base):
    """Live GPS position of drivers with PostGIS Geography point."""
    __tablename__ = "driver_locations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    driver_uid = Column(String(128), ForeignKey("drivers.driver_uid", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    location = Column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    accuracy_meters = Column(Float, nullable=True)
    heading_degrees = Column(Float, nullable=True)
    speed_mps = Column(Float, nullable=True)
    is_available = Column(Boolean, default=True, nullable=False, index=True)
    captured_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    driver = relationship("Driver", back_populates="location")

    __table_args__ = (
        Index("idx_driver_locations_location_gist", "location", postgresql_using="gist"),
        Index("idx_driver_locations_avail_updated", "is_available", "updated_at"),
    )


class Ride(Base):
    """Ride lifecycle recording."""
    __tablename__ = "rides"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    passenger_uid = Column(String(128), ForeignKey("users.firebase_uid"), nullable=False, index=True)
    driver_uid = Column(String(128), ForeignKey("drivers.driver_uid"), nullable=True, index=True)
    selected_driver_uid = Column(String(128), ForeignKey("drivers.driver_uid"), nullable=True, index=True)
    pickup_location = Column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    dropoff_location = Column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    dropoff_lat = Column(Float, nullable=True)
    dropoff_lng = Column(Float, nullable=True)
    destination_label = Column(String(256), nullable=True)
    passenger_name = Column(String(128), nullable=True)
    idempotency_key = Column(String(64), unique=True, nullable=True, index=True)
    status = Column(String(32), default="requested", nullable=False, index=True)  # requested, accepted, in_progress, completed, cancelled, rejected
    distance_km = Column(Float, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    notes = Column(Text, nullable=True)
    request_expires_at = Column(DateTime(timezone=True), nullable=True, index=True)
    cancelled_by = Column(String(32), nullable=True)
    cancel_reason = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    passenger = relationship("User", back_populates="rides_as_passenger", foreign_keys=[passenger_uid])
    driver = relationship("Driver", back_populates="rides", foreign_keys=[driver_uid])
    selected_driver = relationship("Driver", foreign_keys=[selected_driver_uid])

    __table_args__ = (
        Index("idx_rides_pickup_location_gist", "pickup_location", postgresql_using="gist"),
        Index("idx_rides_idempotency_key", "idempotency_key"),
    )


class Destination(Base):
    """Saved / recent destinations for passenger search."""
    __tablename__ = "destinations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_uid = Column(String(128), ForeignKey("users.firebase_uid", ondelete="CASCADE"), nullable=False, index=True)
    place_name = Column(String(256), nullable=False)
    display_label = Column(String(256), nullable=False)
    location = Column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User", back_populates="destinations")

    __table_args__ = (
        Index("idx_destinations_location_gist", "location", postgresql_using="gist"),
        Index("idx_destinations_user_created", "user_uid", "created_at"),
    )
