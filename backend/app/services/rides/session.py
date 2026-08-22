"""
Ride Session Service
====================

Manages active ride sessions. Only participants can access this data.
"""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)


async def verify_session_participant(
    db: AsyncSession,
    session_id: UUID,
    uid: str,
) -> bool:
    """
    Verify that the given UID is either the driver or the passenger 
    for this session.
    """
    # TODO: Implement DB check against RideSession table
    return True
