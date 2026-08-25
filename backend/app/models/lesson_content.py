from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    pass


class LessonContent(Base):
    """Admin override layer for a file-based (legacy) lesson — a row only
    exists once an admin has edited that lesson. Null fields mean 'use the
    bundled file'. No id column: lessonId itself is the primary key."""

    __tablename__ = "LessonContent"

    lessonId: Mapped[str] = mapped_column(String, primary_key=True)
    materialText: Mapped[str | None] = mapped_column(String, nullable=True)
    videoUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    audioUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    # No DB-level default (confirmed via information_schema) — set client-side.
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)
    # Plain string, no real FK to User — matches the Prisma schema exactly
    # (manual-cascade-style loose reference, not an enforced relation).
    updatedById: Mapped[str | None] = mapped_column(String, nullable=True)
