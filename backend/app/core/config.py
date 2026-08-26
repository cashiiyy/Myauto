"""
MyAuto Backend Configuration
============================
Centralised settings loaded from environment variables or .env file.
"""

from __future__ import annotations

from functools import lru_cache
from typing import List
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Application ───────────────────────────────────────────────────────────
    app_env: str = "production"
    app_host: str = "0.0.0.0"
    app_port: int = 8919
    log_level: str = "info"

    # ── Database ──────────────────────────────────────────────────────────────
    database_url: str = (
        "postgresql+asyncpg://myauto:password@postgres:5432/myauto"
    )
    database_sync_url: str = (
        "postgresql://myauto:password@postgres:5432/myauto"
    )

    # ── External Services ─────────────────────────────────────────────────────
    photon_url: str = "http://photon:2322"
    photon_timeout_seconds: float = 5.0

    valhalla_url: str = "http://valhalla:8002"
    valhalla_timeout_seconds: float = 8.0

    # ── Feature Flags ─────────────────────────────────────────────────────────
    # All new features default to FALSE to strictly preserve existing behavior
    enable_postgres: bool = False
    enable_valhalla: bool = False
    enable_firebase_auth: bool = False

    # ── Firebase Admin SDK ────────────────────────────────────────────────────
    firebase_credentials_path: str = "/app/secrets/firebase-service-account.json"
    firebase_service_account_path: str = "secrets/serviceAccountKey.json"
    firebase_project_id: str = "myauto-493fc"

    # ── Redis (optional caching / presence) ───────────────────────────────────
    redis_url: str = "redis://redis:6379/0"

    # ── Security & CORS ───────────────────────────────────────────────────────
    cors_origins: str = ""

    # ── Location Quality & Matching Defaults ───────────────────────────────────
    max_match_accuracy_meters: float = 100.0
    max_match_age_seconds: int = 30
    initial_radius_km: float = 2.0
    fallback_radius_km: float = 5.0
    max_radius_km: float = 10.0

    @property
    def cors_origins_list(self) -> List[str]:
        if not self.cors_origins:
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() in ("production", "prod")

    @property
    def is_development(self) -> bool:
        return self.app_env.lower() in ("development", "dev")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()

