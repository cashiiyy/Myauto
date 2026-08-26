"""
Ride Repository
===============
Handles Ride lifecycle persistence in PostgreSQL.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from geoalchemy2.functions import ST_MakePoint, ST_SetSRID
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Ride


class RideRepository:
    """Repository interface for Ride models."""

    def __init__(self, session: Optional[AsyncSession] = None):
        self.session = session

    async def create_ride_request(
        self,
        passenger_uid: str,
        pickup_lat: float,
        pickup_lon: float,
        dropoff_lat: Optional[float] = None,
        dropoff_lon: Optional[float] = None,
        notes: Optional[str] = None,
    ) -> Optional[Ride]:
        if not self.session:
            return None

        pickup_geom = func.ST_SetSRID(func.ST_MakePoint(pickup_lon, pickup_lat), 4326)
        dropoff_geom = (
            func.ST_SetSRID(func.ST_MakePoint(dropoff_lon, dropoff_lat), 4326)
            if dropoff_lat is not None and dropoff_lon is not None
            else None
        )

        ride = Ride(
            id=uuid.uuid4(),
            passenger_uid=passenger_uid,
            pickup_location=pickup_geom,
            dropoff_location=dropoff_geom,
            status="requested",
            notes=notes,
        )
        self.session.add(ride)
        await self.session.flush()
        return ride

    async def get_by_id(self, ride_id: uuid.UUID) -> Optional[Ride]:
        if not self.session:
            return None
        stmt = select(Ride).where(Ride.id == ride_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def update_status(
        self,
        ride_id: uuid.UUID,
        status: str,
        driver_uid: Optional[str] = None,
    ) -> Optional[Ride]:
        if not self.session:
            return None

        ride = await self.get_by_id(ride_id)
        if ride:
            ride.status = status
            if driver_uid:
                ride.driver_uid = driver_uid
            ride.updated_at = datetime.now(timezone.utc)
            await self.session.flush()
        return ride
