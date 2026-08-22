"""
Redis Key Templates — single source of truth.
=============================================

All Redis key patterns are defined here.
No other module should construct Redis keys by hand.
"""

from __future__ import annotations


class RedisKeys:
    """
    Centralised Redis key templates.

    Naming convention:  <entity>:<aspect>:<id>
    """

    # ── Driver live state ──────────────────────────────────────────────────────

    @staticmethod
    def driver_presence(driver_uid: str) -> str:
        """hash: {state, last_seen_ms, connection_id}  TTL=35s"""
        return f"driver:presence:{driver_uid}"

    @staticmethod
    def driver_location(driver_uid: str) -> str:
        """hash: {lat, lng, accuracy, speed, heading, seq, received_at}  TTL=30s"""
        return f"driver:location:{driver_uid}"

    @staticmethod
    def driver_availability(driver_uid: str) -> str:
        """string: driver state enum  TTL=35s"""
        return f"driver:availability:{driver_uid}"

    # ── Passenger live state ───────────────────────────────────────────────────

    @staticmethod
    def passenger_location(passenger_uid: str) -> str:
        """hash: {lat, lng, accuracy, captured_at}  TTL=60s"""
        return f"passenger:location:{passenger_uid}"

    # ── Ride state ─────────────────────────────────────────────────────────────

    @staticmethod
    def ride_session(ride_id: str) -> str:
        """hash: {driver_uid, passenger_uid, state, created_at}  TTL=3600s"""
        return f"ride:session:{ride_id}"

    @staticmethod
    def ride_rejected(ride_id: str) -> str:
        """set: driver UIDs that have rejected this ride  TTL=600s"""
        return f"ride:rejected:{ride_id}"

    # ── Atomic reservation lock ────────────────────────────────────────────────

    @staticmethod
    def driver_lock(driver_uid: str) -> str:
        """string: passenger_uid that holds the lock  TTL=10s (SET NX EX)"""
        return f"lock:driver:{driver_uid}"

    # ── GEO sorted set ─────────────────────────────────────────────────────────

    DRIVERS_GEO: str = "drivers:geo"
    """Redis GEO sorted set of all currently-active drivers."""

    # ── WebSocket connections ──────────────────────────────────────────────────

    @staticmethod
    def ws_connection(uid: str) -> str:
        """hash: {connection_id, role, last_heartbeat}"""
        return f"ws:connections:{uid}"

    # ── Sequence tracking (prevent out-of-order GPS updates) ──────────────────

    @staticmethod
    def driver_sequence(driver_uid: str) -> str:
        """string: last accepted sequence number  TTL=60s"""
        return f"driver:seq:{driver_uid}"
