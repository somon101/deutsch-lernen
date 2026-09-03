import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.lesson_node import LessonNode


class LessonNodeMedia(Base):
    """One instructional-language variant of a video/audio LessonNode's file
    (§ course content language, 2026-09-04). LessonNode.mediaUrl itself is
    left in place, untouched, as the pre-migration value (read as a
    same-locale fallback only for a node that predates this table) — every
    node going forward is expected to have a row here per locale it
    supports. A locale with no real recording yet may temporarily point at
    the same URL as another locale (an explicit, intentional placeholder,
    not a silent fallback) until a real localized file replaces it."""

    __tablename__ = "LessonNodeMedia"
    __table_args__ = (UniqueConstraint("lessonNodeId", "locale", name="LessonNodeMedia_lessonNodeId_locale_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    lessonNodeId: Mapped[str] = mapped_column(String, ForeignKey("LessonNode.id", ondelete="CASCADE"), nullable=False)
    locale: Mapped[str] = mapped_column(String, nullable=False)
    mediaUrl: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    node: Mapped["LessonNode"] = relationship()
