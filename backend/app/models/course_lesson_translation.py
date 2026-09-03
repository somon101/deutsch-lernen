import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.course_lesson import CourseLesson


class CourseLessonTranslation(Base):
    """One instructional-language variant of a CourseLesson's flat text
    fields (§ course content language, 2026-09-04). Only meaningful for a
    lesson still on its legacy flat fields, or the ones a converted graph
    lesson keeps as a safe rollback reference (see Material's own docstring)
    — a graph lesson's real "material" node content is localized instead via
    MaterialTranslation/MaterialBlockTranslation. Same locale-as-data pattern
    as CourseTranslation; see that model's docstring for why."""

    __tablename__ = "CourseLessonTranslation"
    __table_args__ = (
        UniqueConstraint("courseLessonId", "locale", name="CourseLessonTranslation_courseLessonId_locale_key"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    courseLessonId: Mapped[str] = mapped_column(
        String, ForeignKey("CourseLesson.id", ondelete="CASCADE"), nullable=False
    )
    locale: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str] = mapped_column(String, nullable=False, default="")
    materialText: Mapped[str] = mapped_column(String, nullable=False, default="")
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    lesson: Mapped["CourseLesson"] = relationship()
