"""
Valhalla Routing Service
========================
Connects to Valhalla routing engine via HTTPX.
Implements the RoutingService interface.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)


class RoutingService(ABC):
    """Abstract interface for turn-by-turn routing services."""

    @abstractmethod
    async def get_route(
        self,
        from_lat: float,
        from_lon: float,
        to_lat: float,
        to_lon: float,
        costing: str = "auto",
    ) -> Optional[Dict[str, Any]]:
        """Calculate a route from origin to destination."""
        pass


class ValhallaService(RoutingService):
    """HTTPX-based client for Valhalla routing."""

    def __init__(self, base_url: Optional[str] = None, timeout_seconds: Optional[float] = None):
        settings = get_settings()
        self.base_url = (base_url or settings.valhalla_url).rstrip("/")
        self.timeout = timeout_seconds or settings.valhalla_timeout_seconds
        self.enabled = settings.enable_valhalla

    async def get_route(
        self,
        from_lat: float,
        from_lon: float,
        to_lat: float,
        to_lon: float,
        costing: str = "auto",
    ) -> Optional[Dict[str, Any]]:
        if not self.enabled:
            logger.debug("Valhalla routing is disabled via ENABLE_VALHALLA flag.")
            return None

        payload = {
            "locations": [
                {"lat": from_lat, "lon": from_lon},
                {"lat": to_lat, "lon": to_lon},
            ],
            "costing": costing,
            "directions_options": {"units": "kilometres"},
        }

        url = f"{self.base_url}/route"

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(url, json=payload)
                if response.status_code != 200:
                    logger.warning("Valhalla returned non-200 status: %s", response.status_code)
                    return None

                data = response.json()
                return self._parse_trip(data.get("trip", {}))

        except httpx.TimeoutException:
            logger.warning("Valhalla route calculation timed out.")
            return None
        except Exception as e:
            logger.error("Error communicating with Valhalla service: %s", e)
            return None

    def _parse_trip(self, trip: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        summary = trip.get("summary", {})
        legs = trip.get("legs", [])

        if not summary or not legs:
            return None

        distance_km = float(summary.get("length", 0.0))
        duration_seconds = int(summary.get("time", 0))
        shape = legs[0].get("shape", "") if legs else ""

        return {
            "distance_km": round(distance_km, 2),
            "duration_seconds": duration_seconds,
            "shape": shape,
            "units": "kilometres",
        }
