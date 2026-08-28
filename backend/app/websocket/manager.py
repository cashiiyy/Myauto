"""
WebSocket Connection Manager
============================

Tracks connected clients, handles broadcast routing, and keeps heartbeats.
Integrates Redis Pub/Sub for multi-worker / multi-container event fan-out.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Optional

from fastapi import WebSocket

from app.redis.keys import RedisKeys
from app.schemas.event import WebSocketEvent

logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self):
        # Maps uid -> WebSocket (connections local to this worker process)
        self.active_connections: dict[str, WebSocket] = {}
        self._pubsub_task: Optional[asyncio.Task] = None
        self._pubsub = None

    async def start_pubsub_listener(self):
        """Start listening for Redis Pub/Sub messages across workers."""
        if self._pubsub_task and not self._pubsub_task.done():
            return

        try:
            from app.redis.client import get_redis
            redis_client = await get_redis()
            self._pubsub = redis_client.pubsub()
            await self._pubsub.psubscribe("ws:channel:*", RedisKeys.WS_BROADCAST_CHANNEL)
            self._pubsub_task = asyncio.create_task(self._listen_pubsub())
            logger.info("WebSocket Redis Pub/Sub fan-out listener started.")
        except Exception as e:
            logger.warning("Could not start Redis Pub/Sub listener (single-worker mode): %s", e)

    async def _listen_pubsub(self):
        """Worker background loop receiving messages published by other workers."""
        try:
            async for message in self._pubsub.listen():
                if message["type"] not in ("pmessage", "message"):
                    continue

                channel = message["channel"]
                data_str = message["data"]

                try:
                    payload = json.loads(data_str) if isinstance(data_str, str) else data_str
                except Exception:
                    continue

                if channel == RedisKeys.WS_BROADCAST_CHANNEL:
                    await self._send_local_broadcast(payload)
                elif channel.startswith("ws:channel:"):
                    target_uid = channel[len("ws:channel:"):]
                    await self._send_local(target_uid, payload)
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.error("Redis Pub/Sub listener error: %s", exc)

    async def stop_pubsub_listener(self):
        """Stop Pub/Sub listener on shutdown."""
        if self._pubsub_task:
            self._pubsub_task.cancel()
            try:
                await self._pubsub_task
            except asyncio.CancelledError:
                pass
            self._pubsub_task = None

        if self._pubsub:
            try:
                await self._pubsub.punsubscribe()
                await self._pubsub.close()
            except Exception:
                pass
            self._pubsub = None

    async def connect(self, websocket: WebSocket, uid: str):
        await websocket.accept()
        self.active_connections[uid] = websocket
        logger.info("WebSocket connected locally for UID: %s (total local: %d)", uid, len(self.active_connections))

    def disconnect(self, uid: str):
        if uid in self.active_connections:
            del self.active_connections[uid]
            logger.info("WebSocket disconnected locally for UID: %s (total local: %d)", uid, len(self.active_connections))

    async def _send_local(self, uid: str, payload: dict):
        """Send message directly to a locally connected client."""
        ws = self.active_connections.get(uid)
        if ws:
            try:
                await ws.send_json(payload)
            except Exception as e:
                logger.error("Failed to send local WebSocket message to %s: %s", uid, e)
                self.disconnect(uid)

    async def _send_local_broadcast(self, payload: dict):
        """Broadcast directly to all locally connected clients."""
        disconnected_uids = []
        for uid, ws in list(self.active_connections.items()):
            try:
                await ws.send_json(payload)
            except Exception:
                disconnected_uids.append(uid)

        for uid in disconnected_uids:
            self.disconnect(uid)

    async def send_personal_message(self, event: WebSocketEvent, uid: str):
        """
        Send event to a specific user.
        Publishes to Redis Pub/Sub for multi-worker delivery, with local fallback.
        """
        payload = event.to_json()
        published = False

        try:
            from app.redis.client import get_redis
            redis_client = await get_redis()
            channel = RedisKeys.ws_user_channel(uid)
            await redis_client.publish(channel, json.dumps(payload))
            published = True
        except Exception:
            published = False

        # If Redis publishing is unavailable or not running, deliver locally
        if not published:
            await self._send_local(uid, payload)

    async def broadcast(self, event: WebSocketEvent):
        """
        Broadcast event to all connected users across all workers.
        """
        payload = event.to_json()
        published = False

        try:
            from app.redis.client import get_redis
            redis_client = await get_redis()
            await redis_client.publish(RedisKeys.WS_BROADCAST_CHANNEL, json.dumps(payload))
            published = True
        except Exception:
            published = False

        if not published:
            await self._send_local_broadcast(payload)


manager = ConnectionManager()
