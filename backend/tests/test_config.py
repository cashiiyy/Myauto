"""
Tests for Core Configuration & Feature Flags
"""

import pytest
from app.core.config import Settings


def test_default_config_feature_flags_disabled():
    """Verify all optional services default to disabled for safe fallback."""
    settings = Settings(
        _env_file=None,
    )
    assert settings.enable_postgres is False
    assert settings.enable_valhalla is False
    assert settings.enable_firebase_auth is False
    assert settings.app_port == 8919
    assert settings.photon_url == "http://photon:2322"
    assert settings.valhalla_url == "http://valhalla:8002"


def test_cors_origins_parsing():
    """Verify CORS origins string is parsed into list."""
    settings = Settings(cors_origins="http://localhost:3000, https://myauto.app")
    assert settings.cors_origins_list == ["http://localhost:3000", "https://myauto.app"]

    settings_empty = Settings(cors_origins="")
    assert settings_empty.cors_origins_list == ["*"]
