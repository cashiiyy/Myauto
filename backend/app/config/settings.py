"""
MyAuto Backend — Centralised Configuration
==========================================

All tunable values live here.  Nothing else in the codebase should
hard-code thresholds, TTLs, radii, or secret paths.

Values are loaded from environment variables (or a .env file when
running locally).  The .env.example file documents every variable.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Application ───────────────────────────────────────────────────────────
    app_env: str = "development"
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    app_log_level: str = "info"

    # ── Database ──────────────────────────────────────────────────────────────
    database_url: str = (
        "postgresql+asyncpg://myauto:myauto@localhost:5432/myauto"
    )
    database_sync_url: str = (
        "postgresql://myauto:myauto@localhost:5432/myauto"
    )
    postgres_host: str = "localhost"
    postgres_port: int = 5432
    postgres_db: str = "myauto"
    postgres_user: str = "myauto"
    postgres_password: str = "myauto"

    # ── Redis ─────────────────────────────────────────────────────────────────
    redis_url: str = "redis://localhost:6379/0"
    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_db: int = 0

    # ── Firebase ──────────────────────────────────────────────────────────────
    firebase_service_account_path: str = "secrets/serviceAccountKey.json"
    firebase_project_id: str = "myauto-493fc"

    # ── Security ──────────────────────────────────────────────────────────────
    cors_origins: str = "http://localhost:3000"
    rate_limit_per_minute: int = 60
    max_payload_bytes: int = 1_048_576  # 1 MB

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    # ── Location Quality ──────────────────────────────────────────────────────
    # GPS accuracy thresholds (metres)
    max_match_accuracy_meters: float = 100.0
    accuracy_high_confidence_meters: float = 25.0
    accuracy_acceptable_meters: float = 50.0

    # Maximum age of a GPS fix accepted for matching (seconds)
    max_match_age_seconds: int = 30

    # Plausible maximum auto-rickshaw speed (m/s).  ~72 km/h = 20 m/s
    max_speed_mps: float = 20.0

    # Coordinate bounds — reasonable for India
    lat_min: float = 6.0
    lat_max: float = 37.5
    lon_min: float = 68.0
    lon_max: float = 97.5

    # ── Freshness Thresholds (seconds since last GPS update) ──────────────────
    freshness_live_seconds: int = 5
    freshness_delayed_seconds: int = 15
    freshness_stale_seconds: int = 30
    # Beyond STALE the driver is treated as OFFLINE for matching

    # ── Redis TTLs (seconds) ──────────────────────────────────────────────────
    live_location_ttl_seconds: int = 30
    driver_presence_ttl_seconds: int = 35
    passenger_location_ttl_seconds: int = 60
    ride_session_ttl_seconds: int = 3_600
    ride_rejected_ttl_seconds: int = 600
    driver_lock_ttl_seconds: int = 10

    # ── Matching / Search Radii (km) ─────────────────────────────────────────
    initial_radius_km: float = 2.0
    fallback_radius_km: float = 5.0
    max_radius_km: float = 10.0

    # ── Ride Timeouts ─────────────────────────────────────────────────────────
    driver_response_timeout_seconds: int = 30
    ride_request_expires_seconds: int = 120

    # ── WebSocket ─────────────────────────────────────────────────────────────
    ws_heartbeat_interval_seconds: int = 20
    ws_pong_timeout_seconds: int = 10

    # ── Derived helpers ───────────────────────────────────────────────────────
    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"

    @property
    def firebase_service_account_abs(self) -> Path:
        p = Path(self.firebase_service_account_path)
        if not p.is_absolute():
            # Resolve relative to the backend/ directory
            p = Path(__file__).parent.parent / p
        return p

    @field_validator("app_env")
    @classmethod
    def validate_env(cls, v: str) -> str:
        allowed = {"development", "staging", "production", "test"}
        if v.lower() not in allowed:
            raise ValueError(f"app_env must be one of {allowed}, got {v!r}")
        return v.lower()


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached Settings instance.  Use this everywhere."""
    return Settings()
