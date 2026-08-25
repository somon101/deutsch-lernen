import re

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.user import User

# Latin letters, digits and underscore, compared case-insensitively.
USERNAME_PATTERN = re.compile(r"^[A-Za-z0-9_]+$")
USERNAME_MIN = 3
USERNAME_MAX = 32


def validate_username(value: str) -> str:
    if len(value) < USERNAME_MIN:
        raise ValueError(f"Логин должен содержать не менее {USERNAME_MIN} символов")
    if len(value) > USERNAME_MAX:
        raise ValueError(f"Логин должен содержать не более {USERNAME_MAX} символов")
    if not USERNAME_PATTERN.match(value):
        raise ValueError("Логин может содержать только латинские буквы, цифры и «_», без пробелов и других знаков")
    return value


def normalize_username(username: str) -> str:
    """The value the case-insensitive unique constraint is checked against."""
    return username.lower()


async def conflict_message(
    db: AsyncSession, email: str | None, username_lower: str | None, exclude_user_id: str | None = None
) -> str:
    """Postgres reports a unique-violation without naming the constraint, so
    work out which field actually collided rather than guessing — telling a
    user "email is taken" when it was really the login is worse than
    useless. Shared between the admin user-edit and self-service profile
    endpoints, which both write username/email onto User."""
    email_owner = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none() if email else None
    username_owner = (
        (await db.execute(select(User).where(User.usernameLower == username_lower))).scalar_one_or_none()
        if username_lower
        else None
    )
    email_taken = bool(email_owner and email_owner.id != exclude_user_id)
    username_taken = bool(username_owner and username_owner.id != exclude_user_id)

    if email_taken and username_taken:
        return "Email и логин уже заняты"
    if username_taken:
        return "Такой логин уже занят (регистр букв не учитывается)"
    if email_taken:
        return "Email уже занят"
    return "Email или логин уже заняты"
