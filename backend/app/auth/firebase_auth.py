"""
Firebase Admin SDK Authentication Layer
========================================

This module initialises the Firebase Admin SDK once at application startup
and provides FastAPI dependency functions for token verification and
role-based authorisation.

Security contract
-----------------
* The backend NEVER trusts uid, role, isDriver, isAvailable, or isVerified
  values from request bodies or URL parameters.
* Identity is derived solely from a verified Firebase ID token.
* Role and permission data is fetched server-side from the database.
* Expired and invalid tokens are rejected with HTTP 401.
"""

from __future__ import annotations

import logging
from functools import lru_cache
from pathlib import Path
from typing import Optional

import firebase_admin
from fastapi import Depends, HTTPException, WebSocket, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth as firebase_auth_module
from firebase_admin import credentials
from pydantic import BaseModel

from app.config.settings import get_settings

logger = logging.getLogger(__name__)

# ── Firebase app initialisation ───────────────────────────────────────────────

_firebase_app: Optional[firebase_admin.App] = None


def init_firebase() -> firebase_admin.App:
    """
    Initialise Firebase Admin SDK.
    Idempotent — safe to call multiple times.
    Must be called before any token verification.
    """
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    settings = get_settings()
    sa_path: Path = settings.firebase_service_account_abs

    if sa_path.exists():
        cred = credentials.Certificate(str(sa_path))
        logger.info("Firebase Admin SDK: using service account from %s", sa_path)
    else:
        # Fallback for CI / testing: use Application Default Credentials
        cred = credentials.ApplicationDefault()
        logger.warning(
            "Service account not found at %s — using ApplicationDefault credentials. "
            "This is expected in test environments only.",
            sa_path,
        )

    _firebase_app = firebase_admin.initialize_app(
        cred,
        {"projectId": settings.firebase_project_id},
    )
    logger.info(
        "Firebase Admin SDK initialised for project: %s",
        settings.firebase_project_id,
    )
    return _firebase_app


# ── Verified token model ──────────────────────────────────────────────────────


class VerifiedToken(BaseModel):
    """
    Decoded and verified Firebase ID-token claims.
    This is the authoritative identity object passed to every handler.
    """

    uid: str
    email: Optional[str] = None
    email_verified: bool = False
    # Role is fetched from our DB, not from the token claims
    # (Claims can be set but we don't rely on them as primary authority here)
    firebase_claims: dict = {}

    class Config:
        arbitrary_types_allowed = True


# ── Token verification ────────────────────────────────────────────────────────

_bearer_scheme = HTTPBearer(auto_error=False)


def _verify_id_token(raw_token: str) -> VerifiedToken:
    """
    Verify a Firebase ID token string.

    Raises HTTPException 401 on any verification failure.
    Tokens are verified against Firebase's public keys — no local secret needed.
    """
    try:
        init_firebase()
        decoded = firebase_auth_module.verify_id_token(
            raw_token,
            check_revoked=True,
        )
    except firebase_auth_module.RevokedIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except firebase_auth_module.ExpiredIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please refresh your session.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except firebase_auth_module.InvalidIdTokenError as exc:
        logger.debug("Invalid Firebase token: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except Exception as exc:
        logger.error("Unexpected token verification error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return VerifiedToken(
        uid=decoded["uid"],
        email=decoded.get("email"),
        email_verified=decoded.get("email_verified", False),
        firebase_claims=decoded,
    )


# ── FastAPI dependency functions ──────────────────────────────────────────────


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer_scheme),
) -> VerifiedToken:
    """
    FastAPI dependency: extracts and verifies the Firebase ID token from the
    Authorization: Bearer <token> header.

    Usage::

        @router.get("/protected")
        async def handler(user: VerifiedToken = Depends(get_current_user)):
            ...
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return _verify_id_token(credentials.credentials)


async def get_current_user_ws(websocket: WebSocket) -> VerifiedToken:
    """
    WebSocket authentication helper.
    Reads the token from query param ?token=... or the Authorization header.

    WebSocket clients cannot set arbitrary headers on most platforms so
    we support both methods.
    """
    # 1. Try query parameter
    token = websocket.query_params.get("token")

    # 2. Try Authorization header
    if not token:
        auth_header = websocket.headers.get("authorization", "")
        if auth_header.lower().startswith("bearer "):
            token = auth_header[7:].strip()

    if not token:
        await websocket.close(code=4001, reason="Missing authentication token")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing token")

    return _verify_id_token(token)


# ── Role-based guards ─────────────────────────────────────────────────────────
# These depend on our database for role information.
# They are imported and used by the API layer after DB lookup.


class AuthenticatedUser(BaseModel):
    """Full user context: verified token + DB role."""

    uid: str
    email: Optional[str] = None
    role: str  # 'driver' | 'passenger'
    is_verified: bool = False
    is_available: Optional[bool] = None

    class Config:
        arbitrary_types_allowed = True


def require_driver(user: AuthenticatedUser) -> AuthenticatedUser:
    """Guard: raise 403 if the user is not a driver."""
    if user.role != "driver":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Driver role required.",
        )
    return user


def require_passenger(user: AuthenticatedUser) -> AuthenticatedUser:
    """Guard: raise 403 if the user is not a passenger."""
    if user.role != "passenger":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Passenger role required.",
        )
    return user


def require_verified_driver(user: AuthenticatedUser) -> AuthenticatedUser:
    """Guard: raise 403 if the driver is not verified."""
    require_driver(user)
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Verified driver status required.",
        )
    return user
