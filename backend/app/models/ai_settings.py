from datetime import datetime

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class AiSettings(Base):
    """Single-row table (id is always "singleton") holding the AI provider
    connection the admin configures (§ AI lesson generator, 2026-10-03).
    The API key is stored only encrypted (services/ai_settings.py) and is
    never sent back to a client."""

    __tablename__ = "AiSettings"

    id: Mapped[str] = mapped_column(String, primary_key=True, default="singleton")
    provider: Mapped[str] = mapped_column(String, nullable=False, default="deepseek")
    model: Mapped[str] = mapped_column(String, nullable=False, default="deepseek-chat")
    apiKeyEncrypted: Mapped[str | None] = mapped_column(String, nullable=True)
    # The admin's own lesson-writing rules for the model; NULL = the
    # built-in default (services/ai_lessons.py DEFAULT_RULES_PROMPT).
    systemPrompt: Mapped[str | None] = mapped_column(String, nullable=True)
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)
