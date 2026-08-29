import uuid
from datetime import datetime

from sqlalchemy import DateTime, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Notification(Base):
    """A log of every notification sent (or attempted) — also what the
    manual "Отправить уведомление" button re-sends from. `type` is the
    generic event-type key ("lesson_created" today); courseId/lessonId are a
    loose reference (no FK), same convention as Material/LessonBlock."""

    __tablename__ = "Notification"
    __table_args__ = (Index("Notification_type_createdAt_idx", "type", "createdAt"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    type: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    body: Mapped[str] = mapped_column(String, nullable=False)
    deepLink: Mapped[str | None] = mapped_column(String, nullable=True)
    courseId: Mapped[str | None] = mapped_column(String, nullable=True)
    lessonId: Mapped[str | None] = mapped_column(String, nullable=True)
    createdById: Mapped[str | None] = mapped_column(String, nullable=True)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, server_default="now()")
