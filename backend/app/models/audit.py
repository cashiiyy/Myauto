"""
SQLAlchemy ORM Model — Audit Events
=====================================

Immutable audit trail for security-sensitive actions:
  - SOS triggers
  - contact authorization requests
  - unauthorized access attempts
  - driver state transitions
  - ride state transitions
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import INET, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class AuditEvent(Base):
    """
    Append-only security and operational audit log.
    Records are NEVER deleted or updated.
    """

    __tablename__ = "audit_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # Who performed the action (null for system events)
    actor_id: Mapped[str | None] = mapped_column(
        String(128), nullable=True, index=True
    )  # Firebase UID string
    action: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    # What entity was affected
    entity_type: Mapped[str | None] = mapped_column(String(64), nullable=True)
    entity_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    # Source IP (hashed or masked in production — full for debugging only)
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    # Arbitrary context payload — NO phone numbers, NO tokens
    payload: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )

    def __repr__(self) -> str:
        return f"<AuditEvent action={self.action} actor={self.actor_id} at={self.created_at}>"
