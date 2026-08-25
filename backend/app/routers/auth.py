from fastapi import APIRouter, Depends
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.auth.hash import verify_password
from app.auth.jwt import sign_token
from app.db import get_db
from app.errors import ApiError
from app.models.enums import UserStatus
from app.models.login_event import LoginEvent
from app.models.user import User
from app.schemas.auth import LoginRequest
from app.services.serialize import public_user
from app.services.username import normalize_username
from app.utils import utcnow

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/login")
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    # Login is accepted in any casing: "Ivan", "ivan" and "IVAN" all resolve
    # to the same account via the normalized column.
    result = await db.execute(
        select(User).where(or_(User.usernameLower == normalize_username(body.login), User.email == body.login))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise ApiError(401, "Неверный логин или пароль")
    if user.status != UserStatus.ACTIVE:
        raise ApiError(403, "Учётная запись заблокирована")

    if not verify_password(body.password, user.passwordHash):
        raise ApiError(401, "Неверный логин или пароль")

    now = utcnow()
    user.lastLoginAt = now
    db.add(LoginEvent(userId=user.id, createdAt=now))
    await db.commit()
    await db.refresh(user)

    token = sign_token(user.id)
    return {"token": token, "user": public_user(user)}


@router.get("/me")
async def me(user: User = Depends(require_auth)):
    return {"user": public_user(user)}
