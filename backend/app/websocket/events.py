"""
WebSocket Event Factories
=========================

Functions to generate standardized WebSocket events.
"""

from __future__ import annotations

from typing import Any, Optional

from app.schemas.event import EventType, WebSocketEvent


def create_driver_presence_event(
    driver_uid: str,
    state: str,
    lat: float,
    lng: float,
    freshness: str,
) -> WebSocketEvent:
    return WebSocketEvent(
        type=EventType.DRIVER_PRESENCE,
        payload={
            "driver_uid": driver_uid,
            "state": state,
            "latitude": lat,
            "longitude": lng,
            "freshness": freshness,
        }
    )


def create_ride_requested_event(
    ride_id: str,
    passenger_uid: str,
    pickup_lat: float,
    pickup_lng: float,
) -> WebSocketEvent:
    return WebSocketEvent(
        type=EventType.RIDE_REQUESTED,
        ride_id=ride_id,
        payload={
            "passenger_uid": passenger_uid,
            "pickup_lat": pickup_lat,
            "pickup_lng": pickup_lng,
        }
    )

def create_heartbeat_event() -> WebSocketEvent:
    return WebSocketEvent(type=EventType.HEARTBEAT)

def create_error_event(message: str) -> WebSocketEvent:
    return WebSocketEvent(type=EventType.ERROR, payload={"message": message})
