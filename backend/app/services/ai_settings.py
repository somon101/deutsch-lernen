"""AI provider connection (§ AI lesson generator, 2026-10-03).

The admin pastes the provider's API key once; it is stored encrypted with a
key derived from the server's own JWT_SECRET, so a database dump alone does
not reveal it, and it is never returned to any client — the API only says
whether a key is set and shows its last four characters."""

import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.ai_settings import AiSettings


def _fernet() -> Fernet:
    key = base64.urlsafe_b64encode(hashlib.sha256(f"ai-settings:{settings.jwt_secret}".encode()).digest())
    return Fernet(key)


async def get_ai_settings(db: AsyncSession) -> AiSettings:
    row = await db.get(AiSettings, "singleton")
    if row is None:
        row = AiSettings(id="singleton")
        db.add(row)
        await db.commit()
        await db.refresh(row)
    return row


def decrypt_key(row: AiSettings) -> str | None:
    if not row.apiKeyEncrypted:
        return None
    try:
        return _fernet().decrypt(row.apiKeyEncrypted.encode()).decode()
    except InvalidToken:
        # JWT_SECRET changed since the key was saved — treat as "no key"
        # so the admin is asked to paste it again instead of a 500.
        return None


async def get_api_key(db: AsyncSession) -> tuple[str | None, str]:
    """(key or None, model)."""
    row = await get_ai_settings(db)
    return decrypt_key(row), row.model


async def update_ai_settings(db: AsyncSession, *, api_key: str | None = None, model: str | None = None) -> AiSettings:
    """`api_key=""` removes the key; None leaves it unchanged."""
    row = await get_ai_settings(db)
    if api_key is not None:
        api_key = api_key.strip()
        row.apiKeyEncrypted = _fernet().encrypt(api_key.encode()).decode() if api_key else None
    if model is not None and model.strip():
        row.model = model.strip()
    await db.commit()
    await db.refresh(row)
    return row


def settings_dto(row: AiSettings) -> dict:
    key = decrypt_key(row)
    return {
        "provider": row.provider,
        "model": row.model,
        "hasKey": key is not None,
        "keyHint": key[-4:] if key and len(key) >= 8 else None,
    }
