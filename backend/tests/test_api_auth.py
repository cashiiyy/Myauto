import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
from httpx import ASGITransport, AsyncClient
from fastapi import status
from firebase_admin import auth as firebase_auth_module

from app.main import app
from app.auth.firebase_auth import init_firebase, _verify_id_token


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
        with patch(
            "app.auth.firebase_auth.firebase_auth_module.verify_id_token",
            side_effect=firebase_auth_module.ExpiredIdTokenError("Token expired", None),
        ):
            response = await client.get(
                "/api/drivers/nearby?lat=8.5&lng=76.9",
                headers={"Authorization": "Bearer EXPIRED_TOKEN"},
            )
            assert response.status_code == status.HTTP_401_UNAUTHORIZED
            assert "expired" in response.json()["detail"].lower()


def test_init_firebase_fails_fast_on_directory():
    """Test that a directory mounted at the credential path raises RuntimeError (FATAL AUTH CONFIG)."""
    with tempfile.TemporaryDirectory() as temp_dir:
        fake_settings = MagicMock()
        fake_settings.firebase_auth_mode = "service_account"
        fake_settings.firebase_service_account_path = temp_dir
        fake_settings.firebase_credentials_path = "/nonexistent/path.json"
        fake_settings.firebase_project_id = "test-project"

        with patch("app.auth.firebase_auth.get_settings", return_value=fake_settings):
            with patch("app.auth.firebase_auth._firebase_app", None):
                with patch("firebase_admin.get_app", side_effect=ValueError("No app")):
                    with pytest.raises(RuntimeError) as exc_info:
                        init_firebase()
                    assert "[FATAL AUTH CONFIG]" in str(exc_info.value)


