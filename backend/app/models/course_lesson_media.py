import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.course_lesson import CourseLesson


class CourseLessonMedia(Base):
    """One instructional-language variant of a legacy-flat-field lesson's
    video/audio (§ course content language, 2026-09-04) — the CourseLesson
    counterpart to LessonNodeMedia, for a lesson that has not been converted
    to the graph. `mediaType` is "video" or "audio", matching which flat
    CourseLesson column it stands in for. See LessonNodeMedia's docstring
    for the placeholder-clone convention."""

    __tablename__ = "CourseLessonMedia"
    __table_args__ = (
        UniqueConstraint(
            "courseLessonId", "mediaType", "locale", name="CourseLessonMedia_courseLessonId_mediaType_locale_key"
        ),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    courseLessonId: Mapped[str] = mapped_column(
        String, ForeignKey("CourseLesson.id", ondelete="CASCADE"), nullable=False
    )
    mediaType: Mapped[str] = mapped_column(String, nullable=False)
    locale: Mapped[str] = mapped_column(String, nullable=False)
    url: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    lesson: Mapped["CourseLesson"] = relationship()
