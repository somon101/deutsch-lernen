"""Per-language API keys for external programs (see models/api_key.py)."""

import hashlib
import secrets
from datetime import datetime, timedelta

from fastapi import Depends, Header
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.errors import ApiError
from app.models.api_key import ApiKey
from app.models.language import Language
from app.utils import utcnow

KEY_PREFIX = "pk_"

# What a key may do: "<area>:<action>" (§ API-key permissions, 2026-10-05).
AREAS = ("words", "phrases", "topics", "courses")
ACTIONS = ("read", "write", "delete")
PERMISSIONS = tuple(f"{a}:{x}" for a in AREAS for x in ACTIONS)
# Keys created before permissions existed keep exactly their old rights.
LEGACY_PERMISSIONS = tuple(f"{a}:{x}" for a in ("words", "phrases", "topics") for x in ACTIONS)
# A new key with no explicit choice may only read.
DEFAULT_PERMISSIONS = tuple(f"{a}:read" for a in AREAS)


def clean_permissions(values: list[str] | None) -> list[str]:
    """Known permissions only, in canonical order. Writing or deleting in an
    area implies reading it — an edit you cannot see is not useful."""
    wanted = set(values or [])
    unknown = sorted(wanted - set(PERMISSIONS))
    if unknown:
        raise ApiError(400, f"Неизвестное право: {unknown[0]}")
    for p in list(wanted):
        area, action = p.split(":")
        if action != "read":
            wanted.add(f"{area}:read")
    return [p for p in PERMISSIONS if p in wanted]


def effective_permissions(k: ApiKey) -> list[str]:
    return list(k.permissions) if k.permissions is not None else list(LEGACY_PERMISSIONS)


def _expires_at(days: int | None) -> datetime | None:
    if not days:
        return None
    if days < 0 or days > 3650:
        raise ApiError(400, "Срок действия — от 1 до 3650 дней")
    return utcnow() + timedelta(days=days)


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
        "permissions": effective_permissions(k),
        "expiresAt": k.expiresAt.isoformat() if k.expiresAt else None,
        "expired": bool(k.expiresAt and k.expiresAt <= utcnow()),
    }


async def list_keys(db: AsyncSession, language_id: str) -> list[dict]:
    rows = (await db.execute(select(ApiKey).where(ApiKey.languageId == language_id).order_by(ApiKey.createdAt))).scalars().all()
    return [key_dto(k) for k in rows]


async def create_key(
    db: AsyncSession, language_id: str, name: str, permissions: list[str] | None = None, expires_in_days: int | None = None
) -> dict:
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    perms = clean_permissions(permissions) if permissions is not None else list(DEFAULT_PERMISSIONS)
    if not perms:
        raise ApiError(400, "Выберите хотя бы одно право")
    key = KEY_PREFIX + secrets.token_urlsafe(32)
    row = ApiKey(
        languageId=language_id,
        name=name.strip(),
        keyHash=_hash(key),
        prefix=key[:10],
        createdAt=utcnow(),
        permissions=perms,
        expiresAt=_expires_at(expires_in_days),
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {**key_dto(row), "key": key}


async def update_key(db: AsyncSession, language_id: str, key_id: str, changes: dict) -> dict:
    """Name, permissions and expiry can change at any time; the key itself
    never does. `expiresInDays`: a number counts from now, 0 removes the
    expiry."""
    row = await db.get(ApiKey, key_id)
    if not row or row.languageId != language_id:
        raise ApiError(404, "Ключ не найден")
    if changes.get("name") is not None:
        if not changes["name"].strip():
            raise ApiError(400, "Укажите название ключа")
        row.name = changes["name"].strip()
    if changes.get("permissions") is not None:
        perms = clean_permissions(changes["permissions"])
        if not perms:
            raise ApiError(400, "Выберите хотя бы одно право")
        row.permissions = perms
    if changes.get("expiresInDays") is not None:
        row.expiresAt = _expires_at(changes["expiresInDays"])
    await db.commit()
    await db.refresh(row)
    return key_dto(row)


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
    if row.expiresAt and row.expiresAt <= now:
        raise ApiError(401, "Срок действия API-ключа истёк")
    if row.lastUsedAt is None or now - row.lastUsedAt > timedelta(minutes=5):
        row.lastUsedAt = now
        await db.commit()
    return row


def need(permission: str):
    """FastAPI dependency factory: a valid key that also holds `permission`
    (one of PERMISSIONS); anything else is refused with 403 before the
    endpoint touches the database."""
    assert permission in PERMISSIONS, permission

    async def dependency(key: ApiKey = Depends(require_api_key)) -> ApiKey:
        if permission not in effective_permissions(key):
            raise ApiError(403, f"У ключа нет права «{permission}» — его можно выдать в разделе «API» языка")
        return key

    return dependency
