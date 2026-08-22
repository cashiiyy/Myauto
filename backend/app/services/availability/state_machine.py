"""
Driver State Machine
====================

Enforces valid state transitions for drivers.
The server is authoritative over state.

Valid states:
  OFFLINE
  AVAILABLE
  CONTACTED
  RESERVED
  BUSY
  STALE
"""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


# ── Valid Transitions Map ─────────────────────────────────────────────────────

VALID_TRANSITIONS = {
    "OFFLINE": {"AVAILABLE"},
    "AVAILABLE": {"CONTACTED", "STALE", "OFFLINE"},
    "CONTACTED": {"RESERVED", "AVAILABLE", "OFFLINE"},
    "RESERVED": {"BUSY", "AVAILABLE", "OFFLINE"},
    "BUSY": {"AVAILABLE", "OFFLINE"},
    "STALE": {"OFFLINE", "AVAILABLE"},
}


class InvalidStateTransitionError(ValueError):
    """Raised when an invalid state transition is attempted."""
    pass


def validate_transition(current_state: str, new_state: str) -> None:
    """
    Validate if the transition from current_state to new_state is allowed.
    Raises InvalidStateTransitionError if not.
    """
    if current_state == new_state:
        return  # No-op

    allowed_next = VALID_TRANSITIONS.get(current_state, set())
    if new_state not in allowed_next:
        msg = f"Invalid state transition: {current_state} -> {new_state}"
        logger.error(msg)
        raise InvalidStateTransitionError(msg)
