"""
User Repository
===============
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from app.models.user import User

async def get_user_by_firebase_uid(db: AsyncSession, uid: str) -> Optional[User]:
    result = await db.execute(select(User).where(User.firebase_uid == uid))
    return result.scalar_one_or_none()
