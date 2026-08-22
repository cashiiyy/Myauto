"""
WebSocket Endpoint Handler
==========================

The main `/ws` endpoint implementation.
"""

from __future__ import annotations

import logging
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends

from app.auth.firebase_auth import get_current_user_ws
from app.websocket.manager import manager
from app.websocket.events import create_error_event
import redis.asyncio as aioredis
from app.redis.client import get_redis
from app.redis.keys import RedisKeys

logger = logging.getLogger(__name__)

router = APIRouter()

@router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    # Note: Depends doesn't inject into websockets seamlessly in all FastAPI versions,
    # often we need to resolve it inside the function.
):
    try:
        user = await get_current_user_ws(websocket)
    except Exception as e:
        logger.warning("WebSocket auth failed: %s", e)
        # Auth failed, socket is already closed by get_current_user_ws
        return

    await manager.connect(websocket, user.uid)
    redis_conn = await get_redis()
    
    # Register connection in Redis
    conn_key = RedisKeys.ws_connection(user.uid)
    await redis_conn.hset(conn_key, mapping={"connection_id": str(id(websocket)), "role": "unknown"}) # role would be fetched from DB
    await redis_conn.expire(conn_key, 3600) # Give it an initial long TTL, refreshed on heartbeat

    try:
        while True:
            # We wait for messages from the client (e.g. pongs, explicit commands)
            data = await websocket.receive_json()
            
            # Simple handling for now, in a real system we'd parse with InboundMessage
            if data.get("type") == "pong":
                # Refresh TTL
                await redis_conn.expire(conn_key, 3600)

    except WebSocketDisconnect:
        manager.disconnect(user.uid)
        await redis_conn.delete(conn_key)
        # Also clean up presence if they were a driver (often handled by a separate background task watching for disconnects)
    except Exception as e:
        logger.error("WebSocket error for uid %s: %s", user.uid, e)
        manager.disconnect(user.uid)
        await redis_conn.delete(conn_key)
