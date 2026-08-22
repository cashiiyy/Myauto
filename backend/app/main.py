"""
FastAPI Application Factory and Entrypoint
==========================================
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import api_router
from app.auth.firebase_auth import init_firebase
from app.config.settings import get_settings
from app.database.connection import close_engine
from app.redis.client import close_redis, init_redis
from app.websocket.handler import router as ws_router

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application startup and shutdown events.
    """
    logger.info("Starting up MyAuto backend...")
    
    # 1. Initialize configuration
    settings = get_settings()
    logger.info("Environment: %s", settings.app_env)
    
    # 2. Initialize Redis connection pool
    await init_redis()
    
    # 3. Initialize Firebase Admin SDK
    init_firebase()
    
    # DB engine is initialized lazily on first get_db call,
    # but we could also eager load it here.

    yield  # Application runs here

    logger.info("Shutting down MyAuto backend...")
    
    # 4. Clean up resources
    await close_redis()
    await close_engine()
    logger.info("Shutdown complete.")


def create_app() -> FastAPI:
    """FastAPI factory."""
    settings = get_settings()

    app = FastAPI(
        title="MyAuto Backend",
        description="Centralised Phase 1 Backend for MyAuto",
        version="1.0.0",
        lifespan=lifespan,
    )

    # CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Routers
    app.include_router(api_router)
    app.include_router(ws_router)

    return app


app = create_app()
