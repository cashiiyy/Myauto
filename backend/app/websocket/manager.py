"""
WebSocket Connection Manager
============================

Tracks connected clients, handles broadcast routing, and keeps heartbeats.
"""

from __future__ import annotations

import logging
from typing import Optional

from fastapi import WebSocket

from app.schemas.event import WebSocketEvent

logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self):
        # Maps uid -> WebSocket
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, uid: str):
        await websocket.accept()
        self.active_connections[uid] = websocket
        logger.info("WebSocket connected for UID: %s", uid)

    def disconnect(self, uid: str):
        if uid in self.active_connections:
            del self.active_connections[uid]
            logger.info("WebSocket disconnected for UID: %s", uid)

    async def send_personal_message(self, event: WebSocketEvent, uid: str):
        ws = self.active_connections.get(uid)
        if ws:
            try:
                await ws.send_json(event.to_json())
            except Exception as e:
                logger.error("Failed to send message to %s: %s", uid, e)
                self.disconnect(uid)

    async def broadcast(self, event: WebSocketEvent):
        payload = event.to_json()
        disconnected_uids = []
        for uid, ws in self.active_connections.items():
            try:
                await ws.send_json(payload)
            except Exception:
                disconnected_uids.append(uid)
        
        for uid in disconnected_uids:
            self.disconnect(uid)

manager = ConnectionManager()
