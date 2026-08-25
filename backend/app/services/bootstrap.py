import os

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.hash import hash_password
from app.models.enums import Role, UserStatus
from app.models.user import User
from app.services.username import normalize_username


async def ensure_admin_exists(db: AsyncSession) -> None:
    """Mirrors server/src/bootstrap.ts exactly: makes sure the first admin
    account exists on startup. Idempotent — an existing account (including
    its password) is left untouched. Silently no-ops if any of the three
    required env vars is missing, same as the Node version."""
    email = os.environ.get("ADMIN_EMAIL")
    username = os.environ.get("ADMIN_USERNAME")
    password = os.environ.get("ADMIN_PASSWORD")
    if not email or not username or not password:
        return

    username_lower = normalize_username(username)
    result = await db.execute(select(User).where((User.email == email) | (User.usernameLower == username_lower)))
    if result.scalar_one_or_none():
        return

    user = User(
        firstName=os.environ.get("ADMIN_FIRST_NAME") or "Admin",
        lastName=os.environ.get("ADMIN_LAST_NAME") or "Admin",
        email=email,
        username=username,
        usernameLower=username_lower,
        passwordHash=hash_password(password),
        role=Role.ADMIN,
        status=UserStatus.ACTIVE,
        canEditProfile=True,
    )
    db.add(user)
    await db.commit()
    print(f"Created initial admin account: {username}")
