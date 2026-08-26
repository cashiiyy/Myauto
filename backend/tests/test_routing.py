"""
Tests for Routing API (Valhalla Integration)
"""

from unittest.mock import AsyncMock, patch
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import get_settings
from app.main import app


@pytest.mark.asyncio
async def test_route_disabled_by_default():
    """Verify /api/route returns 503 when ENABLE_VALHALLA=false."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/route?from_lat=8.89&from_lon=76.61&to_lat=8.90&to_lon=76.62")
        assert response.status_code == 503
        assert "disabled" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_route_calculation_when_enabled():
    """Verify route calculation when Valhalla is enabled."""
    mock_route = {
        "distance_km": 4.5,
        "duration_seconds": 540,
        "shape": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
        "units": "kilometres",
    }

    transport = ASGITransport(app=app)
    with patch.object(get_settings(), "enable_valhalla", True):
        with patch("app.api.routing._valhalla_service.get_route", new_callable=AsyncMock, return_value=mock_route):
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.post(
                    "/api/route",
                    json={
                        "from_lat": 8.8932,
                        "from_lon": 76.6141,
                        "to_lat": 8.9100,
                        "to_lon": 76.6300,
                    },
                )
                assert response.status_code == 200
                data = response.json()
                assert data["distance_km"] == 4.5
                assert data["duration_seconds"] == 540
                assert data["shape"] == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

