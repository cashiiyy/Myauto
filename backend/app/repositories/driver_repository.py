"""
Driver & DriverLocation Repository
==================================
Handles Driver profile and live PostGIS location persistence.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from geoalchemy2.functions import ST_Distance, ST_DWithin, ST_MakePoint, ST_SetSRID, ST_X, ST_Y
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Driver, DriverLocation


class DriverRepository:
    def __init__(self, session: Optional[AsyncSession] = None):
        self.session = session

    async def get_by_driver_uid(self, driver_uid: str) -> Optional[Driver]:
        if not self.session:
            return None
        stmt = select(Driver).where(Driver.driver_uid == driver_uid)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()


class DriverLocationRepository:
    """Repository for driver GPS locations in PostgreSQL/PostGIS."""

    def __init__(self, session: Optional[AsyncSession] = None):
        self.session = session

    async def upsert_location(
        self,
        driver_uid: str,
        lat: float,
        lon: float,
        accuracy_meters: Optional[float] = None,
        heading_degrees: Optional[float] = None,
        speed_mps: Optional[float] = None,
        is_available: bool = True,
    ) -> Optional[DriverLocation]:
        if not self.session:
            return None

        stmt = select(DriverLocation).where(DriverLocation.driver_uid == driver_uid)
        result = await self.session.execute(stmt)
        record = result.scalar_one_or_none()

        geom_point = func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326)

        if record:
            record.location = geom_point
            record.accuracy_meters = accuracy_meters
            record.heading_degrees = heading_degrees
            record.speed_mps = speed_mps
            record.is_available = is_available
            record.captured_at = datetime.now(timezone.utc)
            record.updated_at = datetime.now(timezone.utc)
        else:
            record = DriverLocation(
                driver_uid=driver_uid,
                location=geom_point,
                accuracy_meters=accuracy_meters,
                heading_degrees=heading_degrees,
                speed_mps=speed_mps,
                is_available=is_available,
                captured_at=datetime.now(timezone.utc),
            )
            self.session.add(record)

        await self.session.flush()
        return record

    async def find_nearby(
        self,
        lat: float,
        lon: float,
        radius_km: float = 2.0,
        limit: int = 20,
    ) -> List[Dict[str, Any]]:
        if not self.session:
            return []

        center_point = func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326)
        radius_meters = radius_km * 1000.0

        stmt = (
            select(
                DriverLocation.driver_uid,
                func.ST_Y(func.ST_AsGeoJSON(DriverLocation.location)),
                func.ST_X(func.ST_AsGeoJSON(DriverLocation.location)),
                DriverLocation.is_available,
                DriverLocation.heading_degrees,
                DriverLocation.accuracy_meters,
                DriverLocation.updated_at,
                (func.ST_Distance(DriverLocation.location, center_point) / 1000.0).label("distance_km"),
            )
            .where(DriverLocation.is_available.is_(True))
            .where(func.ST_DWithin(DriverLocation.location, center_point, radius_meters))
            .order_by("distance_km")
            .limit(limit)
        )

        try:
            result = await self.session.execute(stmt)
            rows = result.all()
            return [
                {
                    "driver_uid": r[0],
                    "latitude": lat,
                    "longitude": lon,
                    "is_available": r[3],
                    "heading": r[4],
                    "accuracy": r[5],
                    "updated_at": r[6].isoformat() if r[6] else None,
                    "distance_km": float(r[7]) if r[7] else 0.0,
                }
                for r in rows
            ]
        except Exception:
            return []
