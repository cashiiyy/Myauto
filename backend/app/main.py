"""
FastAPI Application Factory and Entrypoint
==========================================
Main application factory with safe, optional service initialization.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import api_router
from app.core.config import get_settings
from app.db.session import close_engine
from app.services.firebase_adapter import init_firebase_sdk
from app.websocket.handler import router as ws_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifecycle manager.
    Safely boots optional services (Redis, Firebase, PostgreSQL) without hard dependencies.
    """
    settings = get_settings()
    logger.info("Starting up MyAuto backend (env: %s, port: %d)...", settings.app_env, settings.app_port)

    # 1. Optional Redis connection
    try:
        from app.redis.client import init_redis
        await init_redis()
    except Exception as e:
        logger.warning("Redis initialization skipped or failed (safe fallback active): %s", e)

    # 2. Optional Firebase initialization
    try:
        init_firebase_sdk()
    except Exception as e:
        logger.warning("Firebase initialization skipped (safe fallback active): %s", e)

    yield  # Application serves requests

    logger.info("Shutting down MyAuto backend...")

    # 3. Cleanup Redis
    try:
        from app.redis.client import close_redis
        await close_redis()
    except Exception as e:
        logger.debug("Redis close ignored: %s", e)

    # 4. Cleanup Database engine
    try:
        await close_engine()
    except Exception as e:
        logger.debug("Database engine close ignored: %s", e)

    logger.info("Shutdown complete.")


def create_app() -> FastAPI:
    """FastAPI application factory."""
    settings = get_settings()

    app = FastAPI(
        title="MyAuto Backend API",
        description="Centralised Backend API for MyAuto",
        version="1.0.0",
        lifespan=lifespan,
    )

    # CORS configuration
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Register API and WebSocket routers
    app.include_router(api_router)
    app.include_router(ws_router)

    return app


app = create_app()
