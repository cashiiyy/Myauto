"""
Tests for Health and Readiness endpoints
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_health_returns_200_and_status_ok():
    """Verify /health returns HTTP 200 with status=ok and service name."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "myauto-api"


@pytest.mark.asyncio
async def test_ready_endpoint_with_postgres_disabled():
    """Verify /ready returns status=ready when optional DB is disabled."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/ready")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ready"
        assert data["service"] == "myauto-api"
        assert data["database"] == "disabled"
