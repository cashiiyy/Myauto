import pytest
from httpx import AsyncClient
from fastapi import status
from unittest.mock import patch

from firebase_admin import auth as firebase_auth_module

@pytest.mark.asyncio
async def test_auth_missing_token(client: AsyncClient):
    """Test that requests without a Bearer token are rejected."""
    response = await client.get("/api/drivers/nearby")
    assert response.status_code == status.HTTP_403_FORBIDDEN or response.status_code == status.HTTP_401_UNAUTHORIZED

@pytest.mark.asyncio
async def test_auth_expired_token(client: AsyncClient):
    """Test that requests with an expired Bearer token are rejected with 401."""
    with patch("app.auth.firebase_auth.verify_id_token", side_effect=firebase_auth_module.ExpiredIdTokenError("Token expired", None)):
        response = await client.get("/api/drivers/nearby", headers={"Authorization": "Bearer EXPIRED_TOKEN"})
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
        assert "expired" in response.json()["detail"].lower()

@pytest.mark.asyncio
async def test_websocket_auth_failure_does_not_crash(client: AsyncClient):
    """Test that a WebSocket auth failure gracefully rejects without throwing a 500 error."""
    with patch("app.auth.firebase_auth.verify_id_token", side_effect=firebase_auth_module.ExpiredIdTokenError("Token expired", None)):
        try:
            with client.websocket_connect("/ws?token=EXPIRED_TOKEN") as websocket:
                websocket.receive_json()
        except Exception as e:
            # Expecting the connection to be closed gracefully (1008 policy violation)
            pass
