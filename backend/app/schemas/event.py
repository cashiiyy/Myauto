"""
Pydantic Schemas — WebSocket Events
=====================================

Every WebSocket event must carry a unique eventId, a type, and a
serverTimestamp.  Clients should deduplicate on eventId.

Versioned envelope::

    {
        "eventId": "uuid",
        "type": "location.update",
        "serverTimestamp": "2024-08-22T10:30:00.000Z",
        "rideId": null,
        "payload": { ... }
    }

Defined event types
-------------------
  location.update        — driver location update
  driver.presence        — driver online/offline/state change
  driver.availability    — driver availability changed
  ride.requested         — match found, notifying driver
  ride.matched           — match found, notifying passenger
  ride.accepted          — driver accepted
  ride.rejected          — driver rejected
  ride.cancelled         — ride cancelled by either party
  ride.completed         — ride marked complete
  sos.triggered          — SOS event (private, not broadcast)
  error                  — server-side error event
  heartbeat              — server-to-client keepalive
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from pydantic import BaseModel, Field


# ── Canonical event types ─────────────────────────────────────────────────────

class EventType:
    LOCATION_UPDATE = "location.update"
    DRIVER_PRESENCE = "driver.presence"
    DRIVER_AVAILABILITY = "driver.availability"
    RIDE_REQUESTED = "ride.requested"
    RIDE_MATCHED = "ride.matched"
    RIDE_ACCEPTED = "ride.accepted"
    RIDE_REJECTED = "ride.rejected"
    RIDE_CANCELLED = "ride.cancelled"
    RIDE_COMPLETED = "ride.completed"
    SOS_TRIGGERED = "sos.triggered"
    ERROR = "error"
    HEARTBEAT = "heartbeat"


# ── Versioned event envelope ──────────────────────────────────────────────────

class WebSocketEvent(BaseModel):
    """
    Canonical WebSocket event envelope.
    Every event sent over the WebSocket must be serialised from this model.
    """

    event_id: str = Field(
        default_factory=lambda: str(uuid.uuid4()),
        description="Unique event ID. Clients must deduplicate on this.",
    )
    type: str = Field(..., description="Event type string (e.g. 'ride.accepted')")
    server_timestamp: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat(),
        description="ISO-8601 UTC timestamp when the event was created on the server",
    )
    ride_id: Optional[str] = Field(
        None, description="Ride session/request ID if applicable"
    )
    payload: Optional[dict[str, Any]] = Field(
        None, description="Event-specific payload"
    )

    def to_json(self) -> dict:
        return self.model_dump(mode="json")


# ── Inbound WebSocket message ──────────────────────────────────────────────────

class InboundMessage(BaseModel):
    """
    Message received from a connected client over WebSocket.
    Clients send actions like pong, ping, subscribe etc.
    """

    type: str = Field(..., description="Message type (e.g. 'pong', 'ping', 'subscribe')")
    payload: Optional[dict[str, Any]] = None
