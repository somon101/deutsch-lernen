"""Per-language API keys for external programs (see models/api_key.py)."""

import hashlib
import secrets
from datetime import timedelta

from fastapi import Depends, Header
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.errors import ApiError
from app.models.api_key import ApiKey
from app.models.language import Language
from app.utils import utcnow

KEY_PREFIX = "pk_"


def _hash(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


def key_dto(k: ApiKey) -> dict:
    return {
        "id": k.id,
        "languageId": k.languageId,
        "name": k.name,
        "prefix": k.prefix,
        "createdAt": k.createdAt.isoformat() if k.createdAt else None,
        "lastUsedAt": k.lastUsedAt.isoformat() if k.lastUsedAt else None,
    }


async def list_keys(db: AsyncSession, language_id: str) -> list[dict]:
    rows = (await db.execute(select(ApiKey).where(ApiKey.languageId == language_id).order_by(ApiKey.createdAt))).scalars().all()
    return [key_dto(k) for k in rows]


async def create_key(db: AsyncSession, language_id: str, name: str) -> dict:
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    key = KEY_PREFIX + secrets.token_urlsafe(32)
    row = ApiKey(languageId=language_id, name=name.strip(), keyHash=_hash(key), prefix=key[:10], createdAt=utcnow())
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {**key_dto(row), "key": key}


async def revoke_key(db: AsyncSession, language_id: str, key_id: str) -> bool:
    row = await db.get(ApiKey, key_id)
    if not row or row.languageId != language_id:
        return False
    await db.delete(row)
    await db.commit()
    return True


async def require_api_key(x_api_key: str | None = Header(default=None), db: AsyncSession = Depends(get_db)) -> ApiKey:
    """FastAPI dependency for /api/v1: the key's language scopes every call."""
    if not x_api_key:
        raise ApiError(401, "Нужен заголовок X-API-Key")
    row = (await db.execute(select(ApiKey).where(ApiKey.keyHash == _hash(x_api_key.strip())))).scalar_one_or_none()
    if not row:
        raise ApiError(401, "Неверный или отозванный API-ключ")
    now = utcnow()
    if row.lastUsedAt is None or now - row.lastUsedAt > timedelta(minutes=5):
        row.lastUsedAt = now
        await db.commit()
    return row
