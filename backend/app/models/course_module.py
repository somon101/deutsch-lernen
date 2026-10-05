import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class CourseModule(Base):
    """A named group of lessons inside a course (§ course modules,
    2026-10-05) — usually one topic, e.g. «Знакомство». Lessons point at it
    through CourseLesson.moduleId; a lesson without a module is shown after
    every module. Lesson.position stays the one learner order, and is kept
    in module order (services/course_modules.py renumber_lessons)."""

    __tablename__ = "CourseModule"
    __table_args__ = (Index("CourseModule_courseId_idx", "courseId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    courseId: Mapped[str] = mapped_column(String, ForeignKey("Course.id", ondelete="CASCADE"), nullable=False)
    # Base column is the Russian title (same convention as Course.title).
    title: Mapped[str] = mapped_column(String, nullable=False)
    titleTg: Mapped[str | None] = mapped_column(String, nullable=True)
    description: Mapped[str] = mapped_column(String, nullable=False, default="")
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
