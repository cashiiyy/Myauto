# backend/app/auth/__init__.py
from .firebase_auth import (
    AuthenticatedUser,
    VerifiedToken,
    get_current_user,
    get_current_user_ws,
    init_firebase,
    require_driver,
    require_passenger,
    require_verified_driver,
)

__all__ = [
    "AuthenticatedUser",
    "VerifiedToken",
    "get_current_user",
    "get_current_user_ws",
    "init_firebase",
    "require_driver",
    "require_passenger",
    "require_verified_driver",
]
