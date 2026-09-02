"""
Firebase Adapters
=================
Adapters for Firebase Authentication, Firestore, and Realtime Database.
Respects ENABLE_FIREBASE_AUTH and degrades gracefully when credentials are absent.
"""

from __future__ import annotations

import logging
import os
from abc import ABC, abstractmethod
from typing import Any, Dict, Optional

from app.core.config import get_settings

logger = logging.getLogger(__name__)

_firebase_initialized = False


def init_firebase_sdk() -> bool:
    """Initialize Firebase Admin SDK if credentials exist and auth is enabled."""
    global _firebase_initialized
    if _firebase_initialized:
        return True

    settings = get_settings()
    if not settings.enable_firebase_auth:
        logger.debug("Firebase auth is disabled via ENABLE_FIREBASE_AUTH flag.")
        return False

    try:
        from app.auth.firebase_auth import init_firebase
        init_firebase()
        _firebase_initialized = True
        return True
    except Exception as e:
        logger.warning("Firebase Admin SDK could not be initialized: %s", e)
        _firebase_initialized = False
        return False


class FirebaseAuthAdapter:
    """Verifies Firebase ID tokens."""

    def __init__(self):
        self.enabled = get_settings().enable_firebase_auth

    async def verify_id_token(self, token: str) -> Optional[Dict[str, Any]]:
        """Verify token and return payload, or None if invalid/disabled."""
        if not self.enabled:
            return None

        if not init_firebase_sdk():
            logger.warning("Attempted to verify token but Firebase is not initialized.")
            return None

        try:
            from firebase_admin import auth
            decoded_token = auth.verify_id_token(token)
            return decoded_token
        except Exception as e:
            logger.warning("Firebase token verification failed: %s", e)
            return None

    async def get_user_display_name(self, uid: str) -> Optional[str]:
        """Fetch user display name from Firebase Admin Auth."""
        if not self.enabled or not init_firebase_sdk():
            return None
        try:
            from firebase_admin import auth
            user_record = auth.get_user(uid)
            return user_record.display_name or (user_record.email.split("@")[0] if user_record.email else None)
        except Exception as e:
            logger.debug("Firebase get_user failed for uid %s: %s", uid, e)
            return None


class FirebaseRealtimeAdapter(ABC):
    """Interface for Firebase Realtime Database paths (active_drivers, ride_shares)."""

    @abstractmethod
    async def get_active_drivers(self) -> Dict[str, Any]:
        """Fetch active_drivers node."""
        pass

    @abstractmethod
    async def get_ride_shares(self) -> Dict[str, Any]:
        """Fetch ride_shares node."""
        pass


class MockFirebaseRealtimeAdapter(FirebaseRealtimeAdapter):
    """Default fallback when direct RTDB sync is not configured."""

    async def get_active_drivers(self) -> Dict[str, Any]:
        return {}

    async def get_ride_shares(self) -> Dict[str, Any]:
        return {}


class FirebaseFirestoreAdapter(ABC):
    """Interface for Firestore collections (users)."""

    @abstractmethod
    async def get_user(self, uid: str) -> Optional[Dict[str, Any]]:
        """Fetch user profile document."""
        pass


class MockFirebaseFirestoreAdapter(FirebaseFirestoreAdapter):
    """Default fallback when Firestore is handled directly on client."""

    async def get_user(self, uid: str) -> Optional[Dict[str, Any]]:
        return None
