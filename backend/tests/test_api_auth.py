import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
import fakeredis.aioredis as fakeredis
from httpx import ASGITransport, AsyncClient
from fastapi import status
from fastapi.testclient import TestClient
from firebase_admin import auth as firebase_auth_module

from app.main import app
from app.auth.firebase_auth import init_firebase, _verify_id_token, VerifiedToken
from app.redis.client import get_redis


@pytest.fixture(autouse=True)
def mock_firebase_init_for_auth_tests():
    """Ensure init_firebase succeeds during mock token verification tests."""
    with patch("app.auth.firebase_auth.init_firebase", return_value=MagicMock()):
        yield


@pytest.mark.asyncio
async def test_auth_missing_token():
    """Test that requests without a Bearer token are rejected with 401."""
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


@pytest.mark.asyncio
async def test_auth_invalid_audience_token_rejected():
    """Test that tokens with mismatched audience (e.g. myauto-493fc instead of myauto-dd21e) are rejected."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch(
            "app.auth.firebase_auth.firebase_auth_module.verify_id_token",
            side_effect=firebase_auth_module.InvalidIdTokenError(
                'Firebase ID token has incorrect "aud" (audience) claim. Expected: myauto-dd21e but got: myauto-493fc'
            ),
        ):
            response = await client.get(
                "/api/drivers/nearby?lat=8.5&lng=76.9",
                headers={"Authorization": "Bearer TOKEN_WITH_WRONG_AUD"},
            )
            assert response.status_code == status.HTTP_401_UNAUTHORIZED
            assert "Invalid authentication token" in response.json()["detail"]


@pytest.mark.asyncio
async def test_auth_valid_canonical_token():
    """Test that a valid ID token for canonical project myauto-dd21e is accepted."""
    redis = await fakeredis.FakeRedis(decode_responses=True)
    async def override_get_redis():
        return redis
    app.dependency_overrides[get_redis] = override_get_redis
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.auth.firebase_auth.firebase_auth_module.verify_id_token",
                return_value={
                    "uid": "passenger_canonical_1",
                    "email": "user@myauto.test",
                    "email_verified": True,
                    "aud": "myauto-dd21e",
                    "iss": "https://securetoken.google.com/myauto-dd21e",
                },
            ):
                response = await client.get(
                    "/api/drivers/nearby?lat=8.5&lng=76.9",
                    headers={"Authorization": "Bearer VALID_CANONICAL_TOKEN"},
                )
                assert response.status_code == status.HTTP_200_OK
    finally:
        app.dependency_overrides.pop(get_redis, None)
        await redis.aclose()


def test_init_firebase_fails_fast_on_directory():
    """Test that a directory mounted at the credential path raises RuntimeError (FATAL AUTH CONFIG)."""
    with tempfile.TemporaryDirectory() as temp_dir:
        fake_settings = MagicMock()
        fake_settings.firebase_auth_mode = "service_account"
        fake_settings.firebase_service_account_path = temp_dir
        fake_settings.firebase_credentials_path = "/nonexistent/path.json"
        fake_settings.firebase_project_id = "myauto-dd21e"

        with patch("app.auth.firebase_auth.get_settings", return_value=fake_settings):
            with patch("app.auth.firebase_auth._firebase_app", None):
                with patch("firebase_admin.get_app", side_effect=ValueError("No app")):
                    with pytest.raises(RuntimeError) as exc_info:
                        init_firebase()
                    assert "[FATAL AUTH CONFIG]" in str(exc_info.value)


def test_init_firebase_project_mismatch_guard_aborts_startup():
    """Consistency Guard: Refuse startup if configured FIREBASE_PROJECT_ID differs from service account project_id."""
    fake_settings = MagicMock()
    fake_settings.firebase_auth_mode = "service_account"
    fake_settings.firebase_service_account_path = "secrets/serviceAccountKey.json"
    fake_settings.firebase_credentials_path = None
    fake_settings.firebase_project_id = "myauto-dd21e"  # Configured

    fake_cred = MagicMock()
    fake_cred.project_id = "myauto-493fc"  # Mismatched credential

    with patch("app.auth.firebase_auth.get_settings", return_value=fake_settings):
        with patch("app.auth.firebase_auth._firebase_app", None):
            with patch("firebase_admin.get_app", side_effect=ValueError("No app")):
                with patch("pathlib.Path.exists", return_value=True):
                    with patch("pathlib.Path.is_file", return_value=True):
                        with patch("firebase_admin.credentials.Certificate", return_value=fake_cred):
                            with pytest.raises(RuntimeError) as exc_info:
                                init_firebase()
                            assert "Firebase project mismatch!" in str(exc_info.value)
                            assert "myauto-dd21e" in str(exc_info.value)
                            assert "myauto-493fc" in str(exc_info.value)


def test_init_firebase_project_match_succeeds():
    """Consistency Guard: Startup succeeds when configured FIREBASE_PROJECT_ID matches credential project_id."""
    fake_settings = MagicMock()
    fake_settings.firebase_auth_mode = "service_account"
    fake_settings.firebase_service_account_path = "secrets/serviceAccountKey.json"
    fake_settings.firebase_credentials_path = None
    fake_settings.firebase_project_id = "myauto-dd21e"

    fake_cred = MagicMock()
    fake_cred.project_id = "myauto-dd21e"

    with patch("app.auth.firebase_auth.get_settings", return_value=fake_settings):
        with patch("app.auth.firebase_auth._firebase_app", None):
            with patch("firebase_admin.get_app", side_effect=ValueError("No app")):
                with patch("pathlib.Path.exists", return_value=True):
                    with patch("pathlib.Path.is_file", return_value=True):
                        with patch("firebase_admin.credentials.Certificate", return_value=fake_cred):
                            with patch("firebase_admin.initialize_app", return_value=MagicMock()) as mock_init:
                                app_instance = init_firebase()
                                assert app_instance is not None
                                mock_init.assert_called_once()


def test_ws_auth_missing_token_closes_cleanly():
    """Test that WebSocket connection without token is closed with code 4001."""
    client = TestClient(app)
    with pytest.raises(Exception):
        with client.websocket_connect("/ws") as websocket:
            pass


def test_ws_auth_invalid_token_closes_cleanly():
    """Test that WebSocket connection with invalid token is closed cleanly with 4001."""
    client = TestClient(app)
    with patch(
        "app.auth.firebase_auth.firebase_auth_module.verify_id_token",
        side_effect=firebase_auth_module.InvalidIdTokenError("Invalid token"),
    ):
        with pytest.raises(Exception):
            with client.websocket_connect("/ws?token=invalid_token") as websocket:
                pass


def test_ws_auth_valid_canonical_token_connects():
    """Test that WebSocket connection with valid canonical token connects and stays alive."""
    client = TestClient(app)
    with patch(
        "app.auth.firebase_auth.firebase_auth_module.verify_id_token",
        return_value={
            "uid": "ws_test_user_1",
            "email": "ws@myauto.test",
            "aud": "myauto-dd21e",
        },
    ):
        with patch("app.websocket.handler.get_redis") as mock_get_redis:
            mock_redis = MagicMock()
            mock_redis.hset = MagicMock()
            mock_redis.expire = MagicMock()
            mock_redis.delete = MagicMock()

            async def async_hset(*args, **kwargs): pass
            async def async_expire(*args, **kwargs): pass
            async def async_delete(*args, **kwargs): pass

            mock_redis.hset.side_effect = async_hset
            mock_redis.expire.side_effect = async_expire
            mock_redis.delete.side_effect = async_delete

            async def async_get_redis(): return mock_redis
            mock_get_redis.side_effect = async_get_redis

            with client.websocket_connect("/ws?token=valid_token") as websocket:
                websocket.send_json({"type": "ping"})
                data = websocket.receive_json()
                assert data["type"] == "heartbeat"
