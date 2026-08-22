"""
Location Freshness Service
==========================

Determines the freshness state of a location fix based on its age.
"""

from __future__ import annotations

import time

from app.config.settings import get_settings
from app.schemas.location import LocationUpdate


def determine_freshness(update: LocationUpdate, server_time_ms: int) -> str:
    """
    Determine the freshness of a location fix.
    Returns LIVE | DELAYED | STALE | OFFLINE.
    """
    settings = get_settings()
    
    # Age in seconds
    age_seconds = (server_time_ms - update.captured_at) / 1000.0

    if age_seconds <= settings.freshness_live_seconds:
        return "LIVE"
    if age_seconds <= settings.freshness_delayed_seconds:
        return "DELAYED"
    if age_seconds <= settings.freshness_stale_seconds:
        return "STALE"
    
    return "OFFLINE"
