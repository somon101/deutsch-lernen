import asyncio
from datetime import timedelta

from fastapi import Depends, Header
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import verify_token
from app.db import async_session, get_db
from app.errors import ApiError
from app.models.enums import Role, UserStatus
from app.models.user import User
from app.utils import utcnow

# Matches middleware.ts's ACTIVITY_UPDATE_THROTTLE_MS exactly — a distinct
# constant from the "online" window used in the admin routes (5 min), kept
# separate on purpose, same as the Express version.
_ACTIVITY_UPDATE_THROTTLE = timedelta(minutes=2)


async def _touch_last_active(user_id: str) -> None:
    """Fire-and-forget lastActiveAt bump, in its own session so it can
    outlive the request's own session/transaction — mirrors the Express
    middleware's un-awaited `.catch(() => {})` update exactly: never blocks
    or fails the request it was triggered from."""
    try:
        async with async_session() as session:
            await session.execute(update(User).where(User.id == user_id).values(lastActiveAt=utcnow()))
            await session.commit()
    except Exception:
        pass


async def require_auth(
    authorization: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise ApiError(401, "Не авторизован")

    token = authorization.removeprefix("Bearer ")
    user_id = verify_token(token)
    if not user_id:
        raise ApiError(401, "Недействительный токен")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise ApiError(401, "Пользователь не найден")

    if user.status != UserStatus.ACTIVE:
        raise ApiError(403, "Учётная запись заблокирована")

    if user.lastActiveAt is None or utcnow() - user.lastActiveAt > _ACTIVITY_UPDATE_THROTTLE:
        asyncio.create_task(_touch_last_active(user.id))

    return user


def require_role(*roles: Role):
    async def dependency(user: User = Depends(require_auth)) -> User:
        if user.role not in roles:
            raise ApiError(403, "Недостаточно прав")
        return user

    return dependency


require_admin = require_role(Role.ADMIN)
require_staff = require_role(Role.ADMIN, Role.TEACHER)
