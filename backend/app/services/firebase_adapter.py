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
        import firebase_admin
        from firebase_admin import credentials

        # Check credentials path
        cred_path = settings.firebase_credentials_path
        if not os.path.exists(cred_path):
            cred_path = settings.firebase_service_account_path

        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred, {
                "projectId": settings.firebase_project_id,
            })
            _firebase_initialized = True
            logger.info("Firebase Admin SDK initialized with certificate: %s", cred_path)
            return True

        # Fallback to Application Default Credentials
        firebase_admin.initialize_app(options={
            "projectId": settings.firebase_project_id,
        })
        _firebase_initialized = True
        logger.info("Firebase Admin SDK initialized with Application Default Credentials.")
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
