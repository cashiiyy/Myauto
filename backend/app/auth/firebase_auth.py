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

    # 1. Check if default app is already initialized
    try:
        _firebase_app = firebase_admin.get_app()
        return _firebase_app
    except ValueError:
        pass

    settings = get_settings()
    auth_mode = getattr(settings, "firebase_auth_mode", "service_account").lower()
    project_id = getattr(settings, "firebase_project_id", "myauto-493fc")

    # Primary configured path
    primary_path_str = getattr(settings, "firebase_service_account_path", "/app/secrets/serviceAccountKey.json")
    primary_path = Path(primary_path_str)

    logger.info(
        "[AUTH STARTUP] credential_path=%s exists=%s is_file=%s is_dir=%s auth_mode=%s project_id=%s",
        primary_path,
        primary_path.exists(),
        primary_path.is_file(),
        primary_path.is_dir(),
        auth_mode,
        project_id,
    )

    cred = None

    if auth_mode == "service_account":
        candidate_paths = [
            primary_path_str,
            getattr(settings, "firebase_credentials_path", None),
        ]
        candidate_paths = [p for p in candidate_paths if p]

        for p in candidate_paths:
            path_obj = Path(p)
            if path_obj.exists() and path_obj.is_file():
                try:
                    cred = credentials.Certificate(str(path_obj))
                    logger.info("[AUTH STARTUP] Firebase Admin SDK: loaded certificate from %s", path_obj)
                    break
                except Exception as e:
                    logger.warning("[AUTH STARTUP] Failed loading certificate at %s: %s", path_obj, e)
            elif path_obj.exists() and path_obj.is_dir():
                logger.error(
                    "[FATAL AUTH CONFIG] Path %s is a DIRECTORY, not a JSON certificate file!",
                    path_obj,
                )

        if cred is None:
            err_msg = (
                f"[FATAL AUTH CONFIG] Firebase credential file was not found or is not a regular file. "
                f"Expected: {primary_path_str}. Please ensure serviceAccountKey.json is placed in secrets/ as a valid file."
            )
            logger.critical(err_msg)
            raise RuntimeError(err_msg)

    elif auth_mode == "adc":
        try:
            cred = credentials.ApplicationDefault()
            logger.info("[AUTH STARTUP] Using ApplicationDefault credentials (ADC mode explicitly enabled)")
        except Exception as e:
            err_msg = f"[FATAL AUTH CONFIG] ApplicationDefault credentials failed: {e}"
            logger.critical(err_msg)
            raise RuntimeError(err_msg)

    try:
        _firebase_app = firebase_admin.initialize_app(
            cred,
            {"projectId": project_id},
        )
        logger.info(
            "[AUTH DIAG] Firebase Admin SDK initialised successfully for project: %s",
            project_id,
        )
    except Exception as e:
        logger.error("[AUTH DIAG] Firebase initialize_app failed: %s", e)
        raise

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
    if not raw_token or not raw_token.strip():
        logger.warning("[AUTH DIAG] token_received=False verification_success=False")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token cannot be empty.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        init_firebase()
        decoded = firebase_auth_module.verify_id_token(
            raw_token,
            check_revoked=False,
            clock_skew_seconds=10,
        )
        uid = decoded.get("uid", "")
        logger.info(
            "[AUTH DIAG] token_received=True verification_success=True verified_uid=%s",
            uid,
        )
    except firebase_auth_module.RevokedIdTokenError as exc:
        logger.warning(
            "[AUTH DIAG] token_received=True verification_success=False "
            "verification_exception_type=RevokedIdTokenError verification_exception_message=%s",
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except firebase_auth_module.ExpiredIdTokenError as exc:
        logger.warning(
            "[AUTH DIAG] token_received=True verification_success=False "
            "verification_exception_type=ExpiredIdTokenError verification_exception_message=%s",
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please refresh your session.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except firebase_auth_module.InvalidIdTokenError as exc:
        logger.warning(
            "[AUTH DIAG] token_received=True verification_success=False "
            "verification_exception_type=InvalidIdTokenError verification_exception_message=%s",
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except Exception as exc:
        logger.error(
            "[AUTH DIAG] token_received=True verification_success=False "
            "verification_exception_type=%s verification_exception_message=%s",
            type(exc).__name__,
            exc,
        )
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
    """
    if credentials is None or not credentials.credentials:
        logger.warning("[AUTH DIAG] authorization_header_present=False verification_success=False")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    logger.debug("[AUTH DIAG] authorization_header_present=True")
    return _verify_id_token(credentials.credentials)


async def get_current_user_ws(websocket: WebSocket) -> VerifiedToken:
    """
    WebSocket authentication helper.
    Reads the token from query param ?token=... or the Authorization header.
    """
    # 1. Try query parameter
    token = websocket.query_params.get("token")

    # 2. Try Authorization header
    if not token:
        auth_header = websocket.headers.get("authorization", "")
        if auth_header.lower().startswith("bearer "):
            token = auth_header[7:].strip()

    if not token:
        logger.warning("[AUTH DIAG] ws_token_present=False")
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
