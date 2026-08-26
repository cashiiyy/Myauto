"""
Database Connection & Session Management
========================================
Handles async SQLAlchemy engine and sessionmaker.
Safely degrades when ENABLE_POSTGRES=false.
"""

from __future__ import annotations

import logging
from typing import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import declarative_base

from app.core.config import get_settings

logger = logging.getLogger(__name__)

Base = declarative_base()

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def get_engine() -> AsyncEngine | None:
    """Return the global async engine if PostgreSQL is enabled."""
    global _engine
    settings = get_settings()

    if not settings.enable_postgres:
        return None

    if _engine is None:
        try:
            _engine = create_async_engine(
                settings.database_url,
                echo=(settings.app_env == "development"),
                pool_pre_ping=True,
                pool_size=10,
                max_overflow=20,
            )
            logger.info("Database engine initialized: %s", settings.database_url.split("@")[-1])
        except Exception as e:
            logger.error("Failed to initialize database engine: %s", e)
            _engine = None

    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession] | None:
    """Return the global session factory."""
    global _session_factory
    engine = get_engine()
    if engine is None:
        return None

    if _session_factory is None:
        _session_factory = async_sessionmaker(
            bind=engine,
            class_=AsyncSession,
            expire_on_commit=False,
        )

    return _session_factory


async def get_db() -> AsyncGenerator[AsyncSession | None, None]:
    """Dependency for obtaining an async DB session."""
    factory = get_session_factory()
    if factory is None:
        yield None
        return

    async with factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def close_engine() -> None:
    """Gracefully dispose the database engine on shutdown."""
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
        _engine = None
        _session_factory = None
        logger.info("Database engine closed.")
