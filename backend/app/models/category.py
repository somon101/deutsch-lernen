import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class Category(Base):
    """A word-card category (§ word cards, 2026-08-31) — "Еда", "Семья", etc.
    Global, not per-course/lesson/language: two words from completely
    different lessons (or courses) can share one category row, which is the
    whole point — categories group meaning, not content-authoring location.

    `nameKey` is the same normalized-dedupe idea VocabularyItem.germanKey
    already uses for words, reused here so "get or create a category by
    name" never creates a near-duplicate ("Еда" vs "еда" vs " Еда ")."""

    __tablename__ = "Category"
    __table_args__ = (UniqueConstraint("nameKey", name="Category_nameKey_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name: Mapped[str] = mapped_column(String, nullable=False)
    nameKey: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
