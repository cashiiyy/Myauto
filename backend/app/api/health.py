"""
Health & Readiness Check API
============================
Provides liveness and readiness endpoints.
"""

from __future__ import annotations

import logging
from typing import Any, Dict
from fastapi import APIRouter, Response, status
from sqlalchemy import text

from app.core.config import get_settings
from app.db.session import get_engine

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Health"])


@router.get("/health", status_code=status.HTTP_200_OK)
async def health_check() -> Dict[str, str]:
    """
    Liveness probe.
    Returns 200 OK as long as the FastAPI process is alive.
    """
    return {
        "status": "ok",
        "service": "myauto-api",
    }


@router.get("/ready")
async def readiness_check(response: Response) -> Dict[str, Any]:
    """
    Readiness probe.
    Checks PostgreSQL connectivity if ENABLE_POSTGRES is true.
    """
    settings = get_settings()
    db_status = "disabled"

    if settings.enable_postgres:
        engine = get_engine()
        if engine is None:
            response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
            return {
                "status": "not_ready",
                "service": "myauto-api",
                "database": "uninitialized",
            }

        try:
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            db_status = "connected"
        except Exception as e:
            logger.warning("Readiness DB check failed: %s", e)
            response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
            return {
                "status": "not_ready",
                "service": "myauto-api",
                "database": "unreachable",
            }

    return {
        "status": "ready",
        "service": "myauto-api",
        "database": db_status,
        "environment": settings.app_env,
    }
