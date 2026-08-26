"""
Photon Geocoding Service
========================
Connects to Photon geocoding engine via HTTPX.
Implements the GeocodingService interface.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)


class GeocodingService(ABC):
    """Abstract interface for geocoding services."""

    @abstractmethod
    async def search(
        self,
        query: str,
        limit: int = 5,
        lat: Optional[float] = None,
        lon: Optional[float] = None,
        bbox: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Search places by text query."""
        pass


class PhotonService(GeocodingService):
    """HTTPX-based client for Photon geocoding."""

    def __init__(self, base_url: Optional[str] = None, timeout_seconds: Optional[float] = None):
        settings = get_settings()
        self.base_url = (base_url or settings.photon_url).rstrip("/")
        self.timeout = timeout_seconds or settings.photon_timeout_seconds

    async def search(
        self,
        query: str,
        limit: int = 5,
        lat: Optional[float] = None,
        lon: Optional[float] = None,
        bbox: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        trimmed = query.strip()
        if not trimmed:
            return []

        params: Dict[str, Any] = {
            "q": trimmed,
            "limit": limit,
            "lang": "en",
        }
        if bbox:
            params["bbox"] = bbox
        if lat is not None and lon is not None:
            params["lat"] = lat
            params["lon"] = lon

        settings = get_settings()
        base_url = self.base_url or settings.photon_url.rstrip("/")
        url = f"{base_url}/api"

        headers = {
            "User-Agent": "MyAuto/1.0 (FastAPI Backend; myauto.app)",
            "Accept": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
                response = await client.get(url, params=params, headers=headers)
                if response.status_code != 200:
                    logger.warning("Photon returned non-200 status: %s for url: %s", response.status_code, url)
                    return []

                data = response.json()
                return self._parse_features(data.get("features", []))

        except httpx.TimeoutException:
            logger.warning("Photon request timed out for query: %s", trimmed)
            return []
        except Exception as e:
            logger.error("Error communicating with Photon service: %s", e)
            return []

    def _parse_features(self, features: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        results = []
        for feat in features:
            props = feat.get("properties", {})
            geom = feat.get("geometry", {})
            coords = geom.get("coordinates", [])

            if len(coords) < 2:
                continue

            lon, lat = coords[0], coords[1]
            name = props.get("name", "")
            city = props.get("city") or props.get("town") or props.get("village") or ""
            state = props.get("state", "")
            country = props.get("country", "")

            # Build a pleasant display label
            parts = [p for p in [name, city, state, country] if p]
            display_label = ", ".join(parts) if parts else name or f"{lat:.4f}, {lon:.4f}"

            results.append({
                "name": name or display_label,
                "display_name": display_label,
                "latitude": float(lat),
                "longitude": float(lon),
                "city": city,
                "state": state,
                "country": country,
                "osm_type": props.get("osm_type", ""),
            })

        return results
