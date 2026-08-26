"""
Tests for Geocoding API (Photon Integration)
"""

from unittest.mock import AsyncMock, patch
import pytest
from httpx import ASGITransport, AsyncClient, TimeoutException

from app.main import app


@pytest.mark.asyncio
async def test_empty_geocoding_query_rejected():
    """Verify empty or whitespace-only search query returns 400 Bad Request."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Empty string
        res1 = await client.get("/api/geocode/search?q=")
        assert res1.status_code == 400
        assert "cannot be empty" in res1.json()["detail"]

        # Whitespace string
        res2 = await client.get("/api/geocode/search?q=   ")
        assert res2.status_code == 400
        assert "cannot be empty" in res2.json()["detail"]


@pytest.mark.asyncio
async def test_photon_timeout_handled_gracefully():
    """Verify timeout when communicating with Photon returns empty results without crashing."""
    transport = ASGITransport(app=app)

    with patch("app.api.geocoding._photon_service.search", side_effect=TimeoutException("Connection timed out")):
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/geocode/search?q=Kollam+Beach")
            assert response.status_code == 200
            assert response.json() == []


@pytest.mark.asyncio
async def test_photon_successful_search_parsing():
    """Verify mock Photon response parses into standardized response model."""
    mock_results = [
        {
            "name": "Kollam Railway Station",
            "display_name": "Kollam Railway Station, Kollam, Kerala, India",
            "latitude": 8.8932,
            "longitude": 76.6141,
            "city": "Kollam",
            "state": "Kerala",
            "country": "India",
            "osm_type": "N",
        }
    ]

    transport = ASGITransport(app=app)
    with patch("app.api.geocoding._photon_service.search", new_callable=AsyncMock, return_value=mock_results):
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/geocode/search?q=Kollam")
            assert response.status_code == 200
            data = response.json()
            assert len(data) == 1
            assert data[0]["name"] == "Kollam Railway Station"
            assert data[0]["latitude"] == 8.8932
            assert data[0]["longitude"] == 76.6141
            assert data[0]["city"] == "Kollam"
            assert data[0]["latitude"] == 8.8932
            assert data[0]["longitude"] == 76.6141
            assert data[0]["city"] == "Kollam"
