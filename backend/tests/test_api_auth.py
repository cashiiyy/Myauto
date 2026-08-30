import pytest
from httpx import ASGITransport, AsyncClient
from fastapi import status
from unittest.mock import patch

from firebase_admin import auth as firebase_auth_module
from app.main import app

@pytest.mark.asyncio
async def test_auth_missing_token():
    """Test that requests without a Bearer token are rejected."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/drivers/nearby?lat=8.5&lng=76.9")
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
        assert "Authorization header is required" in response.json()["detail"]

@pytest.mark.asyncio
async def test_auth_expired_token():
    """Test that requests with an expired Bearer token are rejected with 401."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("app.auth.firebase_auth.firebase_auth_module.verify_id_token", side_effect=firebase_auth_module.ExpiredIdTokenError("Token expired", None)):
            response = await client.get("/api/drivers/nearby?lat=8.5&lng=76.9", headers={"Authorization": "Bearer EXPIRED_TOKEN"})
            assert response.status_code == status.HTTP_401_UNAUTHORIZED
            assert "expired" in response.json()["detail"].lower()

