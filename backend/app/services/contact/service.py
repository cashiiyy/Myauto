"""
Contact Service
===============

Provides short-lived authorization tokens or VOIP routing instructions
so that passengers and drivers can communicate without exposing phone numbers.
"""

from __future__ import annotations

import logging
from uuid import UUID

logger = logging.getLogger(__name__)


async def authorize_contact(
    session_id: UUID,
    caller_uid: str,
    target_uid: str,
) -> dict:
    """
    In Phase 2, this will interface with Twilio Proxy or a similar 
    service to generate masked numbers, or provide an RTC token for in-app calls.
    For now, it records the audit event.
    """
    logger.info(
        "Contact authorization requested by %s for %s on session %s",
        caller_uid, target_uid, session_id
    )
    return {"status": "authorized", "method": "in_app_rtc"}
