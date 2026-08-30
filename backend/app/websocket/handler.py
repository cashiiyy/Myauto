"""
WebSocket Endpoint Handler
==========================

The main ``/ws`` endpoint implementation.

Inbound message types
---------------------
  ping              — client keepalive ping, server responds with heartbeat
  pong              — client response to server heartbeat, refreshes TTL
  location_update   — driver sends GPS update over WebSocket (alternative to REST)
  subscribe_ride    — subscribe to events for a specific ride session
  unsubscribe_ride  — unsubscribe from a ride session

All other message types receive an ``error`` response.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.auth.firebase_auth import get_current_user_ws
from app.config.settings import get_settings
from app.redis.client import get_redis
from app.redis.keys import RedisKeys
from app.schemas.event import EventType, InboundMessage, WebSocketEvent
from app.websocket.events import create_error_event, create_heartbeat_event
from app.websocket.manager import manager

logger = logging.getLogger(__name__)
router = APIRouter()


async def _send_heartbeat_loop(websocket: WebSocket, uid: str, interval: int) -> None:
    """Periodically send heartbeat events to the client."""
    while True:
        await asyncio.sleep(interval)
        try:
            event = create_heartbeat_event()
            await websocket.send_json(event.to_json())
        except Exception:
            break  # Connection is dead — outer loop will handle cleanup


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    Authenticated WebSocket endpoint.

    Authentication
    --------------
    Pass the Firebase ID token as a query parameter:
      wss://host/ws?token=<firebase_id_token>

    Or in the Authorization header:
      Authorization: Bearer <firebase_id_token>
    """
    # ── Authentication ────────────────────────────────────────────────────────
    try:
        user = await get_current_user_ws(websocket)
    except Exception as exc:
        logger.warning("WebSocket auth failed: %s", exc)
        try:
            await websocket.accept()
            await websocket.close(code=4001, reason="Auth failed")
        except Exception:
            pass
        return

    uid = user.uid
    settings = get_settings()

    # ── Connection setup ──────────────────────────────────────────────────────
    await manager.connect(websocket, uid)
    redis_conn = await get_redis()

    conn_key = RedisKeys.ws_connection(uid)
    await redis_conn.hset(conn_key, mapping={
        "connection_id": str(id(websocket)),
        "connected_at": str(int(time.time() * 1000)),
    })
    await redis_conn.expire(conn_key, 3600)

    # Start background heartbeat task
    heartbeat_task = asyncio.create_task(
        _send_heartbeat_loop(websocket, uid, settings.ws_heartbeat_interval_seconds)
    )

    logger.info("WebSocket connected: uid=%s", uid)

    # ── Message loop ──────────────────────────────────────────────────────────
    try:
        while True:
            raw = await websocket.receive_text()

            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json(
                    create_error_event("Invalid JSON").to_json()
                )
                continue

            msg_type = data.get("type", "")
            payload = data.get("payload", {})

            # ── ping ─────────────────────────────────────────────────────────
            if msg_type == "ping":
                await redis_conn.expire(conn_key, 3600)
                await websocket.send_json(create_heartbeat_event().to_json())

            # ── pong (response to server's heartbeat) ─────────────────────────
            elif msg_type == "pong":
                await redis_conn.expire(conn_key, 3600)

            # ── location_update (driver GPS via WebSocket) ────────────────────
            elif msg_type == "location_update":
                try:
                    from app.schemas.location import LocationUpdateWithRole
                    from app.services.location.service import (
                        process_driver_location,
                        process_passenger_location,
                    )

                    role = payload.get("role", "driver")
                    update = LocationUpdateWithRole(**payload)

                    if role == "driver":
                        stored = await process_driver_location(update, uid, redis_conn)
                    else:
                        stored = await process_passenger_location(update, uid, redis_conn)

                    # Ack with freshness
                    ack = WebSocketEvent(
                        type=EventType.LOCATION_UPDATE,
                        payload={
                            "accepted": True,
                            "freshness": stored.freshness,
                        },
                    )
                    await websocket.send_json(ack.to_json())

                except (ValueError, TypeError) as exc:
                    await websocket.send_json(
                        create_error_event(f"Location rejected: {exc}").to_json()
                    )

            # ── subscribe_ride ────────────────────────────────────────────────
            elif msg_type == "subscribe_ride":
                ride_id: Optional[str] = payload.get("ride_id")
                if not ride_id:
                    await websocket.send_json(
                        create_error_event("subscribe_ride requires ride_id").to_json()
                    )
                else:
                    # Validate the user is a participant in this ride
                    session_key = RedisKeys.ride_session(ride_id)
                    session = await redis_conn.hgetall(session_key)
                    driver_uid = session.get("driver_uid", "")
                    passenger_uid = session.get("passenger_uid", "")

                    if uid not in (driver_uid, passenger_uid):
                        await websocket.send_json(
                            create_error_event("Not authorized for this ride session").to_json()
                        )
                    else:
                        # Track subscription in Redis
                        await redis_conn.hset(conn_key, "subscribed_ride", ride_id)
                        ack = WebSocketEvent(
                            type="ride.subscribed",
                            ride_id=ride_id,
                            payload={"status": "subscribed"},
                        )
                        await websocket.send_json(ack.to_json())

            # ── unsubscribe_ride ──────────────────────────────────────────────
            elif msg_type == "unsubscribe_ride":
                await redis_conn.hdel(conn_key, "subscribed_ride")

            # ── unknown ───────────────────────────────────────────────────────
            else:
                await websocket.send_json(
                    create_error_event(f"Unknown message type: {msg_type!r}").to_json()
                )

    except WebSocketDisconnect:
        logger.info("WebSocket disconnected: uid=%s", uid)
    except Exception as exc:
        logger.error("WebSocket error for uid %s: %s", uid, exc)
    finally:
        heartbeat_task.cancel()
        manager.disconnect(uid)
        await redis_conn.delete(conn_key)
        logger.info("WebSocket cleanup complete: uid=%s", uid)
