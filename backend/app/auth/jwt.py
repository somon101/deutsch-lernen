from datetime import datetime, timedelta, timezone

import jwt as pyjwt

from app.config import settings

# Matches server/src/auth/jwt.ts exactly: payload is {sub: userId} only (no
# role/email embedded — role is always re-read fresh from DB per request),
# HS256, 30-day expiry, same JWT_SECRET so tokens are interchangeable
# between the old Express backend and this one during the migration.
_ALGORITHM = "HS256"
_EXPIRY = timedelta(days=30)


def sign_token(user_id: str) -> str:
    payload = {"sub": user_id, "exp": datetime.now(timezone.utc) + _EXPIRY}
    return pyjwt.encode(payload, settings.jwt_secret, algorithm=_ALGORITHM)


def verify_token(token: str) -> str | None:
    """Returns the user id (sub claim), or None on any verification failure
    — mirrors jwt.ts's verifyToken, which swallows every error into null."""
    try:
        payload = pyjwt.decode(token, settings.jwt_secret, algorithms=[_ALGORITHM])
        sub = payload.get("sub")
        return sub if isinstance(sub, str) else None
    except pyjwt.PyJWTError:
        return None
