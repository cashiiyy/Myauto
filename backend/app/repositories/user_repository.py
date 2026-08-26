"""
User Repository
===============
Handles User model persistence.
"""

from __future__ import annotations

from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import User


class UserRepository:
    def __init__(self, session: Optional[AsyncSession] = None):
        self.session = session

    async def get_by_firebase_uid(self, firebase_uid: str) -> Optional[User]:
        if not self.session:
            return None
        stmt = select(User).where(User.firebase_uid == firebase_uid)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def create_or_update(
        self,
        firebase_uid: str,
        role: str = "passenger",
        name: Optional[str] = None,
        phone: Optional[str] = None,
    ) -> Optional[User]:
        if not self.session:
            return None

        user = await self.get_by_firebase_uid(firebase_uid)
        if user:
            user.role = role
            if name:
                user.name = name
            if phone:
                user.phone = phone
        else:
            user = User(
                firebase_uid=firebase_uid,
                role=role,
                name=name,
                phone=phone,
            )
            self.session.add(user)

        await self.session.flush()
        return user
