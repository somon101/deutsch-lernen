import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class ApiKey(Base):
    """A key for an external program, scoped to ONE studied language
    (routers/public_api.py). What it may do is `permissions` — a list of
    "<area>:<action>" strings (services/api_keys.py PERMISSIONS); null means
    a key created before permissions existed, which keeps its old rights
    (read/write/delete words, phrases and topics). Only a SHA-256 hash of
    the key is stored; the key itself is shown once, at creation."""

    __tablename__ = "ApiKey"
    __table_args__ = (Index("ApiKey_languageId_idx", "languageId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    languageId: Mapped[str] = mapped_column(String, ForeignKey("Language.id", ondelete="CASCADE"), nullable=False)
    name: Mapped[str] = mapped_column(String, nullable=False)
    keyHash: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    prefix: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    lastUsedAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
    permissions: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    expiresAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
